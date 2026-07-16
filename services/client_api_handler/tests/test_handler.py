import json

from botocore.exceptions import ClientError

import handler
from session_id import derive_session_id


def _api_gateway_event(prompt: str, sub: str = "sub-123") -> dict:
    return {
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": sub}}}},
        "body": json.dumps({"prompt": prompt}),
    }


def test_invoke_agent_returns_aggregated_completion(fake_bedrock):
    result = handler.invoke_agent("sub-123", "What is my deductible?")
    assert result["response"] == "Hello world."
    assert result["sessionId"] == derive_session_id("sub-123")


def test_invoke_agent_passes_derived_session_id_not_client_supplied(fake_bedrock):
    handler.invoke_agent("sub-123", "Hello")
    assert fake_bedrock.last_kwargs["sessionId"] == derive_session_id("sub-123")
    assert fake_bedrock.last_kwargs["agentId"] == "AGENT123"
    assert fake_bedrock.last_kwargs["agentAliasId"] == "ALIAS123"


def test_lambda_handler_happy_path(fake_bedrock):
    event = _api_gateway_event("What is my deductible?")
    response = handler.lambda_handler(event, None)
    body = json.loads(response["body"])

    assert response["statusCode"] == 200
    assert body["response"] == "Hello world."
    assert body["sessionId"] == derive_session_id("sub-123")


def test_lambda_handler_rejects_missing_authenticated_user(fake_bedrock):
    event = {"body": json.dumps({"prompt": "Hello"})}  # no requestContext.authorizer
    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 401


def test_lambda_handler_rejects_empty_prompt(fake_bedrock):
    event = _api_gateway_event("")
    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 400


def test_lambda_handler_rejects_malformed_json_body(fake_bedrock):
    event = {
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": "sub-123"}}}},
        "body": "not-json",
    }
    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 400


def test_lambda_handler_two_different_users_get_different_sessions(fake_bedrock):
    event_a = _api_gateway_event("Hello", sub="user-a")
    event_b = _api_gateway_event("Hello", sub="user-b")

    body_a = json.loads(handler.lambda_handler(event_a, None)["body"])
    body_b = json.loads(handler.lambda_handler(event_b, None)["body"])

    assert body_a["sessionId"] != body_b["sessionId"]


def test_lambda_handler_sanitizes_throttling_error(monkeypatch):
    class ThrottlingClient:
        def invoke_agent(self, **kwargs):
            raise ClientError(
                {"Error": {"Code": "ThrottlingException", "Message": "slow down"}},
                "InvokeAgent",
            )

    monkeypatch.setattr(handler, "_bedrock_agent_runtime", ThrottlingClient())
    event = _api_gateway_event("Hello")
    response = handler.lambda_handler(event, None)
    body = json.loads(response["body"])

    assert response["statusCode"] == 429
    assert "ThrottlingException" not in body["error"]


def test_lambda_handler_sanitizes_unexpected_client_error(monkeypatch):
    class BoomClient:
        def invoke_agent(self, **kwargs):
            raise ClientError(
                {"Error": {"Code": "InternalServerException", "Message": "boom detail"}},
                "InvokeAgent",
            )

    monkeypatch.setattr(handler, "_bedrock_agent_runtime", BoomClient())
    event = _api_gateway_event("Hello")
    response = handler.lambda_handler(event, None)
    body = json.loads(response["body"])

    assert response["statusCode"] == 502
    assert "boom detail" not in body["error"]
