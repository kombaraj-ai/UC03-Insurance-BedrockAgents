import json
import re

import handler


def _create_claim_event(policy_id: str, accident_date: str, description: str, user_sub: str = "sub-123") -> dict:
    return {
        "messageVersion": "1.0",
        "actionGroup": "ClaimsActionGroup",
        "apiPath": "/claims",
        "httpMethod": "POST",
        "sessionId": "session-123",
        "requestBody": {
            "content": {
                "application/json": {
                    "properties": [
                        {"name": "policyId", "type": "string", "value": policy_id},
                        {"name": "accidentDate", "type": "string", "value": accident_date},
                        {"name": "description", "type": "string", "value": description},
                    ]
                }
            }
        },
        "sessionAttributes": {"userSub": user_sub},
        "promptSessionAttributes": {},
    }


def _get_claim_status_event(claim_number: str) -> dict:
    return {
        "messageVersion": "1.0",
        "actionGroup": "ClaimsActionGroup",
        "apiPath": f"/claims/{claim_number}",
        "httpMethod": "GET",
        "sessionId": "session-123",
        "parameters": [{"name": "claimNumber", "type": "string", "value": claim_number}],
        "sessionAttributes": {},
        "promptSessionAttributes": {},
    }


def _response_body(response: dict) -> dict:
    text = response["response"]["responseBody"]["application/json"]["body"]
    return json.loads(text)


def test_create_claim_happy_path(dynamo_tables):
    dynamo_tables["policies"].put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )

    event = _create_claim_event("POL-998877", "2026-06-20", "Hit a deer on the highway.")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 200
    assert body["outcome"] == "CREATED"
    assert re.match(r"^CLM-\d{4}-\d{6}$", body["claimNumber"])
    assert body["assignedAdjuster"] in {"ADJ-001", "ADJ-002", "ADJ-003", "ADJ-004"}

    stored = dynamo_tables["claims"].get_item(Key={"claimNumber": body["claimNumber"]})["Item"]
    assert stored["policyId"] == "POL-998877"
    assert stored["claimStatus"] == "SUBMITTED"
    assert stored["createdByUserSub"] == "sub-123"


def test_create_claim_rejects_inactive_policy(dynamo_tables):
    dynamo_tables["policies"].put_item(
        Item={"policyId": "POL-30044", "lastName": "Chen", "policyStatus": "LAPSED"}
    )

    event = _create_claim_event("POL-30044", "2026-06-20", "Fender bender.")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 409
    assert body["outcome"] == "POLICY_NOT_ACTIVE"


def test_create_claim_unknown_policy(dynamo_tables):
    event = _create_claim_event("POL-00000000", "2026-06-20", "Fender bender.")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 404
    assert body["outcome"] == "POLICY_NOT_FOUND"


def test_create_claim_rejects_future_accident_date(dynamo_tables):
    dynamo_tables["policies"].put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )
    event = _create_claim_event("POL-998877", "2099-01-01", "Time traveling fender bender.")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == "INVALID_INPUT"


def test_create_claim_rejects_malformed_date(dynamo_tables):
    dynamo_tables["policies"].put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )
    event = _create_claim_event("POL-998877", "not-a-date", "Fender bender.")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == "INVALID_INPUT"


def test_create_claim_rejects_empty_description(dynamo_tables):
    dynamo_tables["policies"].put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )
    event = _create_claim_event("POL-998877", "2026-06-20", "")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == "INVALID_INPUT"


def test_create_claim_retries_on_claim_number_collision(dynamo_tables, monkeypatch):
    dynamo_tables["policies"].put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )
    # Pre-existing claim occupies the first candidate ID.
    dynamo_tables["claims"].put_item(
        Item={"claimNumber": "CLM-2026-000001", "policyId": "POL-other", "claimStatus": "SUBMITTED"}
    )

    candidates = iter(["CLM-2026-000001", "CLM-2026-000002"])
    monkeypatch.setattr(handler, "generate_claim_number", lambda now: next(candidates))

    event = _create_claim_event("POL-998877", "2026-06-20", "Hit a deer.")
    body = _response_body(handler.lambda_handler(event, None))

    assert body["outcome"] == "CREATED"
    assert body["claimNumber"] == "CLM-2026-000002"


def test_get_claim_status_found(dynamo_tables):
    dynamo_tables["claims"].put_item(
        Item={
            "claimNumber": "CLM-2026-000042",
            "policyId": "POL-998877",
            "claimStatus": "UNDER_REVIEW",
            "incidentDate": "2026-06-20",
            "adjusterId": "ADJ-002",
            "updatedAt": "2026-06-21T00:00:00Z",
        }
    )
    event = _get_claim_status_event("CLM-2026-000042")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 200
    assert body["status"] == "UNDER_REVIEW"


def test_get_claim_status_not_found(dynamo_tables):
    event = _get_claim_status_event("CLM-2026-999999")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 404
    assert body["outcome"] == "NOT_FOUND"


def test_get_claim_status_rejects_malformed_claim_number(dynamo_tables):
    event = _get_claim_status_event("not-a-claim-number")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 400
    assert body["outcome"] == "INVALID_INPUT"


def test_unhandled_error_is_sanitized(dynamo_tables, monkeypatch):
    def _boom(_policy_id):
        raise RuntimeError("dynamo is on fire")

    monkeypatch.setattr(handler, "get_policy", _boom)
    event = _create_claim_event("POL-998877", "2026-06-20", "Fender bender.")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert response["response"]["httpStatusCode"] == 500
    assert "RuntimeError" not in body["message"]
    assert "dynamo is on fire" not in body["message"]
