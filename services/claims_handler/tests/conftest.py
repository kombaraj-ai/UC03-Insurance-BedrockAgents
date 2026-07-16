import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

SRC_DIR = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))

POLICIES_TABLE_NAME = "test-Policies"
CLAIMS_TABLE_NAME = "test-Claims"


@pytest.fixture(autouse=True)
def aws_credentials(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("POLICIES_TABLE_NAME", POLICIES_TABLE_NAME)
    monkeypatch.setenv("CLAIMS_TABLE_NAME", CLAIMS_TABLE_NAME)


@pytest.fixture
def dynamo_tables(aws_credentials):
    with mock_aws():
        import dynamo_client

        dynamo_client._policies_table.cache_clear()
        dynamo_client._claims_table.cache_clear()

        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        policies = dynamodb.create_table(
            TableName=POLICIES_TABLE_NAME,
            KeySchema=[{"AttributeName": "policyId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "policyId", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        claims = dynamodb.create_table(
            TableName=CLAIMS_TABLE_NAME,
            KeySchema=[{"AttributeName": "claimNumber", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "claimNumber", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        policies.wait_until_exists()
        claims.wait_until_exists()

        yield {"policies": policies, "claims": claims}

        dynamo_client._policies_table.cache_clear()
        dynamo_client._claims_table.cache_clear()
