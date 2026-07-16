#!/usr/bin/env python3
"""Load sample-data/claims.json into the Claims DynamoDB table.

Usage:
    python seed_claims.py --table autoclaim-iq-dev-Claims --region us-east-1

Table name and region can also come from CLAIMS_TABLE_NAME / AWS_REGION env
vars. These sample claims are optional -- they exist only so getClaimStatus
has real pre-existing records to look up during manual/E2E testing; the
createClaim flow works fine against an empty table.
"""
import argparse
import json
import os
from decimal import Decimal
from pathlib import Path

import boto3

SAMPLE_DATA_PATH = Path(__file__).parent / "sample-data" / "claims.json"


def load_items() -> list[dict]:
    raw = json.loads(SAMPLE_DATA_PATH.read_text())
    return json.loads(json.dumps(raw), parse_float=Decimal, parse_int=Decimal)


def seed(table_name: str, region: str) -> int:
    table = boto3.resource("dynamodb", region_name=region).Table(table_name)
    items = load_items()
    with table.batch_writer(overwrite_by_pkeys=["claimNumber"]) as batch:
        for item in items:
            batch.put_item(Item=item)
    return len(items)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--table",
        default=os.environ.get("CLAIMS_TABLE_NAME"),
        required=os.environ.get("CLAIMS_TABLE_NAME") is None,
        help="Claims DynamoDB table name (or set CLAIMS_TABLE_NAME)",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "us-east-1"),
        help="AWS region (or set AWS_REGION)",
    )
    args = parser.parse_args()

    count = seed(args.table, args.region)
    print(f"Seeded {count} claims into '{args.table}' ({args.region}).")


if __name__ == "__main__":
    main()
