"""Real (if simple) adjuster assignment -- not the reference design's
hardcoded "Sarah Jenkins" for every claim. Deterministic hash-based
round-robin over a small roster, so the same claim number always maps to the
same adjuster (useful for tests and for support staff re-deriving the
assignment).
"""
import zlib

ADJUSTER_ROSTER = ["ADJ-001", "ADJ-002", "ADJ-003", "ADJ-004"]


def assign_adjuster(claim_number: str) -> str:
    index = zlib.crc32(claim_number.encode("utf-8")) % len(ADJUSTER_ROSTER)
    return ADJUSTER_ROSTER[index]
