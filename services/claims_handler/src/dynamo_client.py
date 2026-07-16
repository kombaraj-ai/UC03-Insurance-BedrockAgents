"""DynamoDB access for Claims (read/write) and Policies (read-only). Kept
separate from handler.py so business logic can be unit tested against a
real (moto-mocked) table without also exercising Bedrock event parsing.
"""
import os
from functools import lru_cache
from typing import Any, Optional

import boto3
from botocore.exceptions import ClientError


@lru_cache(maxsize=1)
def _claims_table():
    return boto3.resource("dynamodb").Table(os.environ["CLAIMS_TABLE_NAME"])


@lru_cache(maxsize=1)
def _policies_table():
    return boto3.resource("dynamodb").Table(os.environ["POLICIES_TABLE_NAME"])


def get_policy(policy_id: str) -> Optional[dict[str, Any]]:
    response = _policies_table().get_item(Key={"policyId": policy_id})
    return response.get("Item")


def get_claim(claim_number: str) -> Optional[dict[str, Any]]:
    response = _claims_table().get_item(Key={"claimNumber": claim_number})
    return response.get("Item")


def put_claim_if_absent(item: dict[str, Any]) -> bool:
    """Write item and return True, or return False if claimNumber already
    exists (a collision to retry with a freshly generated claim number)."""
    try:
        _claims_table().put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(claimNumber)",
        )
        return True
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise
