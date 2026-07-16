"""Bedrock Agent Action Group Lambda for ClaimsActionGroup (OpenAPI schema).

Handles POST /claims (createClaim) and GET /claims/{claimNumber}
(getClaimStatus) against real DynamoDB records. `POST /claims` is declared
`x-requireConfirmation: ENABLED` in schemas/claims-openapi.yaml, so Bedrock
only invokes this Lambda for that operation after the end user has
explicitly confirmed -- this handler does not need to branch on a pending
state, but it does stay idempotent (conditional PutItem) in case of any
retry after confirmation.
"""
import json
import logging
import os
import re
import sys
from datetime import date, datetime, timezone
from typing import Any, Optional

from adjuster_assignment import assign_adjuster
from claim_id import generate_claim_number
from dynamo_client import get_claim, get_policy, put_claim_if_absent

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
if not logger.handlers:
    logger.addHandler(logging.StreamHandler(sys.stdout))

_POLICY_ID_RE = re.compile(r"^POL-\d{4,8}$")
_CLAIM_NUMBER_RE = re.compile(r"^CLM-\d{4}-\d{6}$")
_MAX_DESCRIPTION_LEN = 2000
_MAX_CLAIM_ID_ATTEMPTS = 5


def _log(message: str, **fields: Any) -> None:
    logger.info(json.dumps({"message": message, **fields}, default=str))


def _extract_request_body_properties(event: dict) -> dict[str, str]:
    props = (
        event.get("requestBody", {})
        .get("content", {})
        .get("application/json", {})
        .get("properties", [])
    )
    return {p["name"]: p.get("value", "") for p in props}


def _extract_path_parameters(event: dict) -> dict[str, str]:
    return {p["name"]: p.get("value", "") for p in event.get("parameters", [])}


def _validate_create_claim(
    policy_id: str, accident_date: str, description: str
) -> Optional[str]:
    if not policy_id or not _POLICY_ID_RE.match(policy_id):
        return "policyId must look like 'POL-12345'."

    try:
        parsed_date = date.fromisoformat(accident_date)
    except (TypeError, ValueError):
        return "accidentDate must be an ISO date (YYYY-MM-DD)."
    if parsed_date > datetime.now(timezone.utc).date():
        return "accidentDate cannot be in the future."

    if not description or len(description) > _MAX_DESCRIPTION_LEN:
        return "description is required and must be under 2000 characters."

    return None


def create_claim(
    policy_id: str, accident_date: str, description: str, created_by: str
) -> dict:
    """Core business logic, free of any Bedrock event shape so it's directly
    unit-testable."""
    validation_error = _validate_create_claim(policy_id, accident_date, description)
    if validation_error:
        return {
            "outcome": "INVALID_INPUT",
            "httpStatusCode": 400,
            "message": validation_error,
        }

    policy = get_policy(policy_id)
    if policy is None:
        return {
            "outcome": "POLICY_NOT_FOUND",
            "httpStatusCode": 404,
            "message": f"No policy found with ID {policy_id}.",
        }

    if policy.get("policyStatus") != "ACTIVE":
        return {
            "outcome": "POLICY_NOT_ACTIVE",
            "httpStatusCode": 409,
            "message": (
                f"Policy {policy_id} is not active "
                f"(status: {policy.get('policyStatus')}); cannot file a new claim."
            ),
        }

    now = datetime.now(timezone.utc)
    for _ in range(_MAX_CLAIM_ID_ATTEMPTS):
        claim_number = generate_claim_number(now)
        adjuster_id = assign_adjuster(claim_number)
        item = {
            "claimNumber": claim_number,
            "policyId": policy_id,
            "claimStatus": "SUBMITTED",
            "incidentDate": accident_date,
            "incidentDescription": description,
            "adjusterId": adjuster_id,
            "createdAt": now.isoformat(),
            "updatedAt": now.isoformat(),
            "createdByUserSub": created_by,
        }
        if put_claim_if_absent(item):
            return {
                "outcome": "CREATED",
                "httpStatusCode": 200,
                "claimNumber": claim_number,
                "status": item["claimStatus"],
                "assignedAdjuster": adjuster_id,
                "message": "Claim successfully filed.",
            }
        _log("claim number collision, retrying", claimNumber=claim_number)

    return {
        "outcome": "ERROR",
        "httpStatusCode": 500,
        "message": "Unable to generate a unique claim number; please try again.",
    }


def get_claim_status(claim_number: str) -> dict:
    if not claim_number or not _CLAIM_NUMBER_RE.match(claim_number):
        return {
            "outcome": "INVALID_INPUT",
            "httpStatusCode": 400,
            "message": "claimNumber must look like 'CLM-2026-000123'.",
        }

    claim = get_claim(claim_number)
    if claim is None:
        return {
            "outcome": "NOT_FOUND",
            "httpStatusCode": 404,
            "message": f"No claim found with number {claim_number}.",
        }

    return {
        "outcome": "FOUND",
        "httpStatusCode": 200,
        "claimNumber": claim["claimNumber"],
        "status": claim.get("claimStatus"),
        "incidentDate": claim.get("incidentDate"),
        "adjusterId": claim.get("adjusterId"),
        "updatedAt": claim.get("updatedAt"),
    }


def _build_response(event: dict, result: dict) -> dict:
    result = dict(result)
    http_status = result.pop("httpStatusCode", 200)
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "apiPath": event.get("apiPath", ""),
            "httpMethod": event.get("httpMethod", ""),
            "httpStatusCode": http_status,
            "responseBody": {
                "application/json": {"body": json.dumps(result, default=str)}
            },
        },
        "sessionAttributes": event.get("sessionAttributes", {}),
        "promptSessionAttributes": event.get("promptSessionAttributes", {}),
    }


def lambda_handler(event: dict, context: Any) -> dict:
    api_path = event.get("apiPath", "")
    http_method = (event.get("httpMethod") or "").upper()
    _log(
        "claims_handler invoked",
        apiPath=api_path,
        httpMethod=http_method,
        sessionId=event.get("sessionId"),
    )

    created_by = event.get("sessionAttributes", {}).get("userSub", "unknown")

    try:
        if api_path == "/claims" and http_method == "POST":
            body_props = _extract_request_body_properties(event)
            result = create_claim(
                body_props.get("policyId", ""),
                body_props.get("accidentDate", ""),
                body_props.get("description", ""),
                created_by,
            )
        elif api_path.startswith("/claims/") and http_method == "GET":
            path_params = _extract_path_parameters(event)
            result = get_claim_status(path_params.get("claimNumber", ""))
        else:
            result = {
                "outcome": "UNSUPPORTED_OPERATION",
                "httpStatusCode": 400,
                "message": f"Unsupported operation {http_method} {api_path}.",
            }
        _log("claims_handler outcome", outcome=result.get("outcome"))
    except Exception:
        logger.exception("Unhandled error in claims_handler")
        result = {
            "outcome": "ERROR",
            "httpStatusCode": 500,
            "message": "An internal error occurred while processing the claim request. Please try again.",
        }

    return _build_response(event, result)
