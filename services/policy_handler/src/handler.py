"""Bedrock Agent Action Group Lambda for PolicyActionGroup (Function schema).

Handles the single function `verifyAndRetrievePolicy`. Real policyholder
verification against DynamoDB -- no hardcoded/mocked responses.
"""
import json
import logging
import os
import re
import sys
from typing import Any, Optional

from dynamo_client import get_policy

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
if not logger.handlers:
    logger.addHandler(logging.StreamHandler(sys.stdout))

_POLICY_ID_RE = re.compile(r"^POL-\d{4,8}$")
_MAX_NAME_LEN = 60

OUTCOME_INVALID_INPUT = "INVALID_INPUT"
OUTCOME_NOT_FOUND = "NOT_FOUND"
OUTCOME_MISMATCH = "LAST_NAME_MISMATCH"
OUTCOME_VERIFIED = "VERIFIED"
OUTCOME_ERROR = "ERROR"


def _log(message: str, **fields: Any) -> None:
    logger.info(json.dumps({"message": message, **fields}, default=str))


def _extract_parameters(event: dict) -> dict[str, str]:
    return {p["name"]: p.get("value", "") for p in event.get("parameters", [])}


def _validate(policy_id: str, last_name: str) -> Optional[str]:
    if not policy_id or not _POLICY_ID_RE.match(policy_id):
        return "policyId must look like 'POL-12345'."
    if not last_name or len(last_name) > _MAX_NAME_LEN:
        return "lastName is required and must be a reasonable length."
    return None


def verify_policy(policy_id: str, last_name: str) -> dict:
    """Core business logic, deliberately free of any Bedrock event shape so
    it's directly unit-testable."""
    validation_error = _validate(policy_id, last_name)
    if validation_error:
        return {"outcome": OUTCOME_INVALID_INPUT, "message": validation_error}

    item = get_policy(policy_id)
    if item is None:
        return {
            "outcome": OUTCOME_NOT_FOUND,
            "message": f"No policy found with ID {policy_id}.",
        }

    if str(item.get("lastName", "")).strip().lower() != last_name.strip().lower():
        # Deliberately generic: never confirm/deny policy existence to a
        # caller who fails the last-name check.
        return {
            "outcome": OUTCOME_MISMATCH,
            "message": "The last name provided does not match our records for this policy.",
        }

    return {
        "outcome": OUTCOME_VERIFIED,
        "policyId": item["policyId"],
        "policyStatus": item.get("policyStatus"),
        "coverageType": item.get("coverageType"),
        "deductible": item.get("deductible"),
        "vehicleMake": item.get("vehicleMake"),
        "vehicleModel": item.get("vehicleModel"),
        "vehicleYear": item.get("vehicleYear"),
        "expirationDate": item.get("expirationDate"),
        "message": "Policy verified successfully.",
    }


def _build_response(event: dict, body: dict) -> dict:
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "function": event.get("function", ""),
            "functionResponse": {
                "responseBody": {"TEXT": {"body": json.dumps(body, default=str)}}
            },
        },
        "sessionAttributes": event.get("sessionAttributes", {}),
        "promptSessionAttributes": event.get("promptSessionAttributes", {}),
    }


def lambda_handler(event: dict, context: Any) -> dict:
    _log(
        "policy_handler invoked",
        actionGroup=event.get("actionGroup"),
        function=event.get("function"),
        sessionId=event.get("sessionId"),
    )

    try:
        params = _extract_parameters(event)
        result = verify_policy(params.get("policyId", ""), params.get("lastName", ""))
        _log("policy_handler outcome", outcome=result.get("outcome"))
    except Exception:
        logger.exception("Unhandled error verifying policy")
        result = {
            "outcome": OUTCOME_ERROR,
            "message": "An internal error occurred while verifying the policy. Please try again.",
        }

    return _build_response(event, result)
