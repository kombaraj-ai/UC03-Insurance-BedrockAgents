"""DynamoDB access for the Policies table. Kept separate from handler.py so
business logic can be unit tested against a real (moto-mocked) table without
needing to also exercise the Bedrock event-parsing/response-envelope code.
"""
import os
from functools import lru_cache
from typing import Any, Optional

import boto3


@lru_cache(maxsize=1)
def _table():
    dynamodb = boto3.resource("dynamodb")
    return dynamodb.Table(os.environ["POLICIES_TABLE_NAME"])


def get_policy(policy_id: str) -> Optional[dict[str, Any]]:
    """Return the policy item for policy_id, or None if it does not exist."""
    response = _table().get_item(Key={"policyId": policy_id})
    return response.get("Item")
