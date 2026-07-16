import json

import handler


def _make_event(policy_id: str, last_name: str) -> dict:
    return {
        "messageVersion": "1.0",
        "actionGroup": "PolicyActionGroup",
        "function": "verifyAndRetrievePolicy",
        "sessionId": "session-123",
        "parameters": [
            {"name": "policyId", "type": "string", "value": policy_id},
            {"name": "lastName", "type": "string", "value": last_name},
        ],
        "sessionAttributes": {},
        "promptSessionAttributes": {},
    }


def _response_body(response: dict) -> dict:
    text = response["response"]["functionResponse"]["responseBody"]["TEXT"]["body"]
    return json.loads(text)


def test_verify_policy_success(policies_table):
    policies_table.put_item(
        Item={
            "policyId": "POL-998877",
            "lastName": "Smith",
            "policyStatus": "ACTIVE",
            "coverageType": "COMPREHENSIVE",
            "deductible": 500,
        }
    )

    event = _make_event("POL-998877", "Smith")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert body["outcome"] == handler.OUTCOME_VERIFIED
    assert body["policyStatus"] == "ACTIVE"
    assert response["response"]["actionGroup"] == "PolicyActionGroup"
    assert response["response"]["function"] == "verifyAndRetrievePolicy"


def test_verify_policy_last_name_case_insensitive(policies_table):
    policies_table.put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )
    event = _make_event("POL-998877", "smith")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == handler.OUTCOME_VERIFIED


def test_verify_policy_wrong_last_name_does_not_leak_existence(policies_table):
    policies_table.put_item(
        Item={"policyId": "POL-998877", "lastName": "Smith", "policyStatus": "ACTIVE"}
    )
    event = _make_event("POL-998877", "Jones")
    body = _response_body(handler.lambda_handler(event, None))

    assert body["outcome"] == handler.OUTCOME_MISMATCH
    assert "POL-998877" not in body["message"]


def test_verify_policy_not_found(policies_table):
    event = _make_event("POL-00000000", "Nobody")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == handler.OUTCOME_NOT_FOUND


def test_verify_policy_rejects_malformed_policy_id_before_dynamo_call(policies_table):
    event = _make_event("not-a-policy-id", "Smith")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == handler.OUTCOME_INVALID_INPUT


def test_verify_policy_rejects_missing_last_name(policies_table):
    event = _make_event("POL-998877", "")
    body = _response_body(handler.lambda_handler(event, None))
    assert body["outcome"] == handler.OUTCOME_INVALID_INPUT


def test_verify_policy_handles_unexpected_error_gracefully(policies_table, monkeypatch):
    def _boom(_policy_id):
        raise RuntimeError("dynamo is on fire")

    monkeypatch.setattr(handler, "get_policy", _boom)
    event = _make_event("POL-998877", "Smith")
    response = handler.lambda_handler(event, None)
    body = _response_body(response)

    assert body["outcome"] == handler.OUTCOME_ERROR
    # No internal exception detail should leak to the caller/model.
    assert "RuntimeError" not in body["message"]
    assert "dynamo is on fire" not in body["message"]
