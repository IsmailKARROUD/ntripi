"""
services/appeal_token.py — Signed links for the public (unauthenticated) appeal form.

A banned user cannot authenticate at all (is_active=False → 403 on every
request), so the "Appeal this decision" entry point in their suspension email
must carry its own credential. That credential is a JWT with scope="appeal".

The scope claim is load-bearing: the API access token (no scope) and the admin
session cookie (scope="admin") are signed with the same SECRET_KEY, so every
consumer MUST verify the scope it expects. Without that check an appeal link
would be interchangeable with an admin session.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt

from app.config import get_settings

# Matches the 30-day re-appeal cooldown — a link outliving that window would
# let a user re-open an already-decided action.
APPEAL_TOKEN_TTL = timedelta(days=30)

_SCOPE = "appeal"


def mint_appeal_token(
    user_id: uuid.UUID,
    target_type: str,
    target_id: uuid.UUID | None,
    log_id: uuid.UUID | None,
) -> str:
    """Sign an appeal link token for the given moderation action."""
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "scope": _SCOPE,
        "target_type": target_type,
        "target_id": str(target_id) if target_id else None,
        "log_id": str(log_id) if log_id else None,
        "iat": now,
        "exp": now + APPEAL_TOKEN_TTL,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_appeal_token(token: str) -> dict | None:
    """Return the token claims, or None if invalid/expired/wrong-scope."""
    settings = get_settings()
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
    except JWTError:
        return None
    # Reject an API access token or admin cookie replayed as an appeal link.
    if payload.get("scope") != _SCOPE:
        return None
    if not payload.get("sub"):
        return None
    return payload


def appeal_link(token: str) -> str:
    """Absolute URL of the public appeal form for this token."""
    return f"{get_settings().share_base_url}/appeal/{token}"
