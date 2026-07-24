"""
services/refresh_token_service.py — Issue, rotate, and revoke refresh tokens.

Refresh tokens are opaque random strings (not JWTs). We store only the
SHA-256 hash, never the raw token — same threat model as password storage.

Rotation chain (theft detection):
  Every refresh consumes one row and creates a successor in the same
  family_id. The consumed row is marked `revoked_at = now()` and its
  `rotated_to` points at the successor.

  If a row that is already revoked is presented again, it's either a buggy
  client retry — or an attacker replaying a stolen token. We can't tell
  them apart, so we assume the worst and revoke the entire family. The
  legitimate holder will be logged out on their next refresh attempt
  (which is correct: they need to re-authenticate to prove they aren't
  the attacker).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models.refresh_token import RefreshToken
from app.services.auth import create_access_token
from app.services.token_util import as_aware_utc, hash_token, new_raw_token


class InvalidGrantError(Exception):
    """Raised when a refresh token is unknown, expired, or revoked."""


def issue(
    db: Session,
    user_id: uuid.UUID,
    family_id: uuid.UUID | None = None,
    user_agent: str | None = None,
) -> tuple[str, RefreshToken]:
    """
    Create a new refresh token row. Returns (raw_token, row). The caller
    must give the raw_token to the client — it's never readable again.

    Pass family_id when rotating; omit it for a fresh login/register.
    """
    settings = get_settings()
    raw = new_raw_token()
    row = RefreshToken(
        user_id=user_id,
        token_hash=hash_token(raw),
        family_id=family_id or uuid.uuid4(),
        expires_at=datetime.now(timezone.utc)
        + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        user_agent=(user_agent or "")[:255] or None,
    )
    db.add(row)
    db.flush()  # populate row.id before any caller writes rotated_to → id
    return raw, row


def rotate(
    db: Session,
    raw_token: str,
    user_agent: str | None = None,
) -> tuple[str, str, RefreshToken]:
    """
    Atomic rotate: consume `raw_token`, return (new_access_token,
    new_refresh_token, new_row).

    Raises InvalidGrantError if the token is unknown, expired, or already
    revoked. On replay of a revoked token, the entire family is revoked
    before raising — this is the theft-detection behaviour.
    """
    token_hash = hash_token(raw_token)

    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    try:
        stmt = stmt.with_for_update()
    except Exception:
        pass  # SQLite (tests) has no row locks
    current = db.execute(stmt).scalar_one_or_none()

    if current is None:
        raise InvalidGrantError("unknown refresh token")

    now = datetime.now(timezone.utc)

    if as_aware_utc(current.expires_at) <= now:
        raise InvalidGrantError("refresh token expired")

    if current.revoked_at is not None:
        # Replay of a revoked token → revoke the whole family.
        # Log the replayer's user_agent for the support trail.
        revoke_family(db, current.family_id, replayer_user_agent=user_agent)
        raise InvalidGrantError("refresh token revoked")

    # Mint successor first so we can store its id on the consumed row.
    new_raw, new_row = issue(
        db,
        user_id=current.user_id,
        family_id=current.family_id,
        user_agent=user_agent,
    )
    current.revoked_at = now
    current.rotated_to = new_row.id

    new_access = create_access_token(subject=str(current.user_id))
    return new_access, new_raw, new_row


def revoke(db: Session, raw_token: str) -> None:
    """
    Mark a single token as revoked. Used by /auth/logout.
    Silently no-ops on unknown / already-revoked tokens — /auth/logout
    must never leak token validity.
    """
    token_hash = hash_token(raw_token)
    row = db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    ).scalar_one_or_none()
    if row is None or row.revoked_at is not None:
        return
    row.revoked_at = datetime.now(timezone.utc)


def revoke_all_for_user(db: Session, user_id: uuid.UUID) -> int:
    """Revoke every still-active refresh token for a user. Used after a
    password reset to log the account out of all existing sessions."""
    result = db.execute(
        update(RefreshToken)
        .where(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=datetime.now(timezone.utc))
    )
    return result.rowcount or 0


def revoke_family(
    db: Session,
    family_id: uuid.UUID,
    replayer_user_agent: str | None = None,
) -> int:
    """
    Revoke every still-active token in a family. Returns the count revoked.
    `replayer_user_agent` is recorded in application logs only (no schema
    field today) — useful when investigating "I got logged out" reports.
    """
    now = datetime.now(timezone.utc)
    result = db.execute(
        update(RefreshToken)
        .where(
            RefreshToken.family_id == family_id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=now)
    )
    # Best-effort log — structured logging would go here in a real app.
    if replayer_user_agent:
        import logging

        logging.getLogger(__name__).warning(
            "refresh_token_theft_detected family_id=%s replayer_ua=%r",
            family_id,
            replayer_user_agent[:255],
        )
    return result.rowcount or 0
