"""Derives the Bedrock `sessionId` deterministically from the authenticated
Cognito `sub` claim.

This is the key hardening over the reference design, which let the caller
supply *any* sessionId string -- an authenticated user could pass another
user's session ID and continue/read their conversation (a session/IDOR
hijack). By deriving sessionId only from the verified JWT `sub` (never from
client input), a caller can only ever address their own session.
"""
import hashlib

# Bedrock InvokeAgent sessionId allows up to 100 characters from
# [0-9a-zA-Z._:-]. A hex digest fits comfortably within that and is stable
# per user.
_SESSION_ID_PREFIX = "u-"


def derive_session_id(user_sub: str) -> str:
    if not user_sub:
        raise ValueError("user_sub is required to derive a session id")
    digest = hashlib.sha256(user_sub.encode("utf-8")).hexdigest()
    return f"{_SESSION_ID_PREFIX}{digest}"
