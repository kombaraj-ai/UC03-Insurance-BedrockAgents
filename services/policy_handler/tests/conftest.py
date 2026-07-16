import os
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

SRC_DIR = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))

TABLE_NAME = "test-Policies"


@pytest.fixture(autouse=True)
def aws_credentials(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("POLICIES_TABLE_NAME", TABLE_NAME)


@pytest.fixture
def policies_table(aws_credentials):
    with mock_aws():
        import dynamo_client

        dynamo_client._table.cache_clear()

        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        table = dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[{"AttributeName": "policyId", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "policyId", "AttributeType": "S"},
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        table.wait_until_exists()
        yield table
        dynamo_client._table.cache_clear()
