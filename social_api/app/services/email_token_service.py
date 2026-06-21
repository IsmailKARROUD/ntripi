"""
services/email_token_service.py — Issue and consume single-use email tokens.

Mirrors refresh_token_service's threat model: the raw token is an opaque
URL-safe random string; only its SHA-256 hash is stored. Tokens are single-use
(used_at is stamped on consume) and expire.
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.email_token import EmailToken

PURPOSE_PASSWORD_RESET = "password_reset"
PURPOSE_EMAIL_VERIFY = "email_verify"


class InvalidTokenError(Exception):
    """Raised when an email token is unknown, expired, used, or wrong-purpose."""


def _hash(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def _as_aware_utc(dt: datetime) -> datetime:
    # SQLite (tests) returns naive datetimes; PostgreSQL returns tz-aware.
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def issue(
    db: Session,
    user_id: uuid.UUID,
    purpose: str,
    ttl: timedelta,
) -> str:
    """Create a token row and return the raw token (never readable again)."""
    raw = secrets.token_urlsafe(32)
    row = EmailToken(
        user_id=user_id,
        token_hash=_hash(raw),
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
        select(EmailToken).where(EmailToken.token_hash == _hash(raw_token))
    ).scalar_one_or_none()

    if row is None or row.purpose != purpose:
        raise InvalidTokenError("unknown token")
    if row.used_at is not None:
        raise InvalidTokenError("token already used")
    if _as_aware_utc(row.expires_at) <= datetime.now(timezone.utc):
        raise InvalidTokenError("token expired")

    row.used_at = datetime.now(timezone.utc)
    return row.user_id
