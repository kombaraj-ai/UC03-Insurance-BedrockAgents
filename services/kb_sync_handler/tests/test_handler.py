import json
from datetime import datetime, timezone

from botocore.exceptions import ClientError
from botocore.stub import Stubber

import handler

_NOW = datetime.now(timezone.utc)


def _ingestion_job_response(job_id: str) -> dict:
    return {
        "ingestionJob": {
            "ingestionJobId": job_id,
            "knowledgeBaseId": "KB123456",
            "dataSourceId": "DS123456",
            "status": "STARTING",
            "startedAt": _NOW,
            "updatedAt": _NOW,
        }
    }


def _s3_event() -> dict:
    return {
        "Records": [
            {
                "eventName": "ObjectCreated:Put",
                "s3": {"bucket": {"name": "kb-docs"}, "object": {"key": "coverage-faq.md"}},
            }
        ]
    }


def test_start_sync_success():
    with Stubber(handler._bedrock_agent) as stubber:
        stubber.add_response(
            "start_ingestion_job",
            _ingestion_job_response("job-1"),
            {"knowledgeBaseId": "KB123456", "dataSourceId": "DS123456"},
        )
        result = handler.start_sync("KB123456", "DS123456")

    assert result == {"status": "STARTED", "ingestionJobId": "job-1"}


def test_start_sync_conflict_is_a_noop():
    with Stubber(handler._bedrock_agent) as stubber:
        stubber.add_client_error(
            "start_ingestion_job",
            service_error_code="ConflictException",
            service_message="A sync job is already running",
        )
        result = handler.start_sync("KB123456", "DS123456")

    assert result == {"status": "ALREADY_RUNNING"}


def test_start_sync_resource_not_found():
    with Stubber(handler._bedrock_agent) as stubber:
        stubber.add_client_error(
            "start_ingestion_job",
            service_error_code="ResourceNotFoundException",
            service_message="No such knowledge base",
        )
        result = handler.start_sync("KB123456", "DS123456")

    assert result == {"status": "NOT_FOUND"}


def test_start_sync_reraises_unexpected_errors():
    with Stubber(handler._bedrock_agent) as stubber:
        stubber.add_client_error(
            "start_ingestion_job",
            service_error_code="ThrottlingException",
            service_message="Rate exceeded",
        )
        try:
            handler.start_sync("KB123456", "DS123456")
            assert False, "expected ClientError to propagate"
        except ClientError as exc:
            assert exc.response["Error"]["Code"] == "ThrottlingException"


def test_lambda_handler_wires_env_vars_and_returns_200():
    with Stubber(handler._bedrock_agent) as stubber:
        stubber.add_response(
            "start_ingestion_job",
            _ingestion_job_response("job-2"),
            {"knowledgeBaseId": "KB123456", "dataSourceId": "DS123456"},
        )
        response = handler.lambda_handler(_s3_event(), None)

    assert response["statusCode"] == 200
    assert json.loads(response["body"])["ingestionJobId"] == "job-2"
