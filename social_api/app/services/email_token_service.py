"""
services/email_token_service.py — Issue and consume single-use email tokens.

Mirrors refresh_token_service's threat model: the raw token is an opaque
URL-safe random string; only its SHA-256 hash is stored. Tokens are single-use
(used_at is stamped on consume) and expire.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.email_token import EmailToken
from app.services.token_util import as_aware_utc, hash_token, new_raw_token

PURPOSE_PASSWORD_RESET = "password_reset"
PURPOSE_EMAIL_VERIFY = "email_verify"


class InvalidTokenError(Exception):
    """Raised when an email token is unknown, expired, used, or wrong-purpose."""


def issue(
    db: Session,
    user_id: uuid.UUID,
    purpose: str,
    ttl: timedelta,
) -> str:
    """Create a token row and return the raw token (never readable again)."""
    raw = new_raw_token()
    row = EmailToken(
        user_id=user_id,
        token_hash=hash_token(raw),
        purpose=purpose,
        expires_at=datetime.now(timezone.utc) + ttl,
    )
    db.add(row)
    db.flush()
    return raw


def consume(db: Session, raw_token: str, purpose: str) -> uuid.UUID:
    """
    Validate and single-use-consume a token for the given purpose. Returns the
    user_id. Raises InvalidTokenError on unknown / expired / used / wrong-purpose.
    The caller commits.
    """
    row = db.execute(
        select(EmailToken).where(EmailToken.token_hash == hash_token(raw_token))
    ).scalar_one_or_none()

    if row is None or row.purpose != purpose:
        raise InvalidTokenError("unknown token")
    if row.used_at is not None:
        raise InvalidTokenError("token already used")
    if as_aware_utc(row.expires_at) <= datetime.now(timezone.utc):
        raise InvalidTokenError("token expired")

    row.used_at = datetime.now(timezone.utc)
    return row.user_id
