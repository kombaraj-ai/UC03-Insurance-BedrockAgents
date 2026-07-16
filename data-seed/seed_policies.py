#!/usr/bin/env python3
"""Load sample-data/policies.json into the Policies DynamoDB table.

Usage:
    python seed_policies.py --table autoclaim-iq-dev-Policies --region us-east-1

Table name and region can also come from POLICIES_TABLE_NAME / AWS_REGION
env vars (these are exactly the names Terraform outputs for the dev
environment, so `terraform output` piped into env vars works directly).
"""
import argparse
import json
import os
from decimal import Decimal
from pathlib import Path

import boto3

SAMPLE_DATA_PATH = Path(__file__).parent / "sample-data" / "policies.json"


def load_items() -> list[dict]:
    raw = json.loads(SAMPLE_DATA_PATH.read_text())
    # DynamoDB's boto3 resource API requires Decimal, not float/int-mixed types,
    # for numeric attributes.
    return json.loads(json.dumps(raw), parse_float=Decimal, parse_int=Decimal)


def seed(table_name: str, region: str) -> int:
    table = boto3.resource("dynamodb", region_name=region).Table(table_name)
    items = load_items()
    with table.batch_writer(overwrite_by_pkeys=["policyId"]) as batch:
        for item in items:
            batch.put_item(Item=item)
    return len(items)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--table",
        default=os.environ.get("POLICIES_TABLE_NAME"),
        required=os.environ.get("POLICIES_TABLE_NAME") is None,
        help="Policies DynamoDB table name (or set POLICIES_TABLE_NAME)",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "us-east-1"),
        help="AWS region (or set AWS_REGION)",
    )
    args = parser.parse_args()

    count = seed(args.table, args.region)
    print(f"Seeded {count} policies into '{args.table}' ({args.region}).")


if __name__ == "__main__":
    main()
