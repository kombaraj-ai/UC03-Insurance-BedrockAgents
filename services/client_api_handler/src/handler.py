"""Client-facing Lambda behind API Gateway (Cognito JWT-authenticated). Calls
bedrock-agent-runtime:InvokeAgent and returns the aggregated completion.
"""
import json
import logging
import os
import sys
from typing import Any, Iterable

import boto3
from botocore.exceptions import ClientError

from session_id import derive_session_id

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
if not logger.handlers:
    logger.addHandler(logging.StreamHandler(sys.stdout))

_MAX_INPUT_LEN = 4000

_bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")


def _log(message: str, **fields: Any) -> None:
    logger.info(json.dumps({"message": message, **fields}, default=str))


def _extract_completion_text(stream_events: Iterable[dict]) -> str:
    """Concatenate the `chunk.bytes` payloads from an InvokeAgent response
    stream into the final completion text. Kept as a pure function, free of
    any boto3/EventStream machinery, so it's directly unit-testable against
    a plain list of event dicts."""
    parts = []
    for event in stream_events:
        chunk = event.get("chunk")
        if chunk and "bytes" in chunk:
            data = chunk["bytes"]
            parts.append(data.decode("utf-8") if isinstance(data, (bytes, bytearray)) else data)
    return "".join(parts)


def _extract_claims(event: dict) -> dict:
    return (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )


def invoke_agent(user_sub: str, input_text: str) -> dict:
    """Core business logic, free of the API Gateway event shape so it's
    directly unit-testable."""
    session_id = derive_session_id(user_sub)
    agent_id = os.environ["AGENT_ID"]
    agent_alias_id = os.environ["AGENT_ALIAS_ID"]

    response = _bedrock_agent_runtime.invoke_agent(
        agentId=agent_id,
        agentAliasId=agent_alias_id,
        sessionId=session_id,
        inputText=input_text,
        sessionState={"sessionAttributes": {"userSub": user_sub}},
    )
    completion = _extract_completion_text(response["completion"])
    return {"response": completion, "sessionId": session_id}


def _json_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event: dict, context: Any) -> dict:
    claims = _extract_claims(event)
    user_sub = claims.get("sub", "")

    if not user_sub:
        # Defense in depth: API Gateway's JWT authorizer should already have
        # rejected an unauthenticated request before this Lambda runs.
        return _json_response(401, {"error": "Missing authenticated user identity."})

    try:
        body = json.loads(event.get("body") or "{}")
    except (json.JSONDecodeError, TypeError):
        return _json_response(400, {"error": "Request body must be valid JSON."})

    input_text = body.get("prompt", "")
    if not input_text or not isinstance(input_text, str) or len(input_text) > _MAX_INPUT_LEN:
        return _json_response(
            400, {"error": "`prompt` is required and must be a non-empty string."}
        )

    _log("client_api invoked", userSub=user_sub, inputLength=len(input_text))

    try:
        result = invoke_agent(user_sub, input_text)
        return _json_response(200, result)
    except ClientError as exc:
        logger.exception("Bedrock InvokeAgent failed")
        error_code = exc.response["Error"]["Code"]
        if error_code == "ThrottlingException":
            return _json_response(
                429, {"error": "The assistant is busy right now, please try again shortly."}
            )
        return _json_response(
            502, {"error": "The assistant is temporarily unavailable, please try again."}
        )
    except Exception:
        logger.exception("Unhandled error invoking agent")
        return _json_response(500, {"error": "An internal error occurred. Please try again."})
