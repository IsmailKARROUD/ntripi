"""
services/token_util.py — Shared primitives for opaque-token services.

Refresh tokens and email tokens follow the same threat model: the raw token
is an opaque URL-safe random string, and only its SHA-256 hash is ever stored
(same as password storage). These helpers keep that logic in one place so the
hashing and timezone-normalization rules can't drift between the two services.

keyed_hash is the other half: an identifier that must be recognised again but
never read back — a reporter's IP, a blocked sign-up address.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timezone


def hash_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def keyed_hash(value: str, key: str) -> str:
    """HMAC-SHA256 of `value` under `key`, as hex.

    Keyed, not a bare SHA-256: IP and email addresses are guessable, so a plain
    hash is reversed by hashing candidates. Without the key it cannot even be
    tested. Rotating the key retires every stored hash at once.
    """
    return hmac.new(key.encode(), value.encode(), hashlib.sha256).hexdigest()


def as_aware_utc(dt: datetime) -> datetime:
    # SQLite (tests) returns naive datetimes; PostgreSQL returns tz-aware.
    # Normalize so comparisons never raise TypeError across backends.
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def new_raw_token() -> str:
    # 32 bytes → ~43 char base64url string. URL-safe so it can be passed
    # through HTTP request bodies and headers without further escaping.
    return secrets.token_urlsafe(32)
