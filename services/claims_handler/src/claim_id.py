"""Real claim-number generation -- not the reference design's `"CLM-" +
timestamp`. Collision handling (retry on conflict) lives in handler.py via
the conditional PutItem in dynamo_client.put_claim_if_absent.
"""
import random
from datetime import datetime, timezone
from typing import Optional


def generate_claim_number(now: Optional[datetime] = None) -> str:
    now = now or datetime.now(timezone.utc)
    suffix = f"{random.randint(0, 999_999):06d}"
    return f"CLM-{now.year}-{suffix}"
