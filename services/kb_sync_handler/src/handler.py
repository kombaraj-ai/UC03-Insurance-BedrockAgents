"""S3 event -> Bedrock Knowledge Base ingestion trigger.

Fires whenever an object is created/removed in the KB source-docs bucket.
Starts an ingestion job so the Knowledge Base's S3 Vectors index stays in
sync automatically -- no manual "Sync" click required.
"""
import json
import logging
import os
import sys
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
if not logger.handlers:
    logger.addHandler(logging.StreamHandler(sys.stdout))

_bedrock_agent = boto3.client("bedrock-agent")


def _log(message: str, **fields: Any) -> None:
    logger.info(json.dumps({"message": message, **fields}, default=str))


def start_sync(knowledge_base_id: str, data_source_id: str) -> dict:
    """Start an ingestion job. Treat "already syncing" as a logged no-op
    rather than retrying/erroring -- a burst of S3 events from a bulk upload
    would otherwise cause a retry storm against a single in-flight job."""
    try:
        response = _bedrock_agent.start_ingestion_job(
            knowledgeBaseId=knowledge_base_id,
            dataSourceId=data_source_id,
        )
        job_id = response["ingestionJob"]["ingestionJobId"]
        _log("ingestion job started", ingestionJobId=job_id)
        return {"status": "STARTED", "ingestionJobId": job_id}
    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        if error_code == "ConflictException":
            _log("ingestion job already running, skipping", errorCode=error_code)
            return {"status": "ALREADY_RUNNING"}
        if error_code == "ResourceNotFoundException":
            logger.error(
                json.dumps(
                    {
                        "message": "knowledge base or data source not found",
                        "knowledgeBaseId": knowledge_base_id,
                        "dataSourceId": data_source_id,
                    }
                )
            )
            return {"status": "NOT_FOUND"}
        raise


def lambda_handler(event: dict, context: Any) -> dict:
    knowledge_base_id = os.environ["KNOWLEDGE_BASE_ID"]
    data_source_id = os.environ["DATA_SOURCE_ID"]

    records = event.get("Records", [])
    _log("kb_sync_handler invoked", recordCount=len(records))

    result = start_sync(knowledge_base_id, data_source_id)
    return {"statusCode": 200, "body": json.dumps(result)}
