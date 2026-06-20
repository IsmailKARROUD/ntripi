"""
services/auth.py — Password hashing, verification, and JWT management.

Why bcrypt?
  - bcrypt is a purpose-built password hashing algorithm with a built-in
    work factor (cost). As hardware gets faster, you can increase the cost
    to keep brute-force attacks expensive.
  - It automatically salts each hash, so identical passwords produce
    different hashes (prevents rainbow table attacks).
  - Unlike MD5/SHA, bcrypt is intentionally slow — that's a feature.

Why JWT?
  - Stateless: the server doesn't need to store session data. The token
    itself contains all the claims (user ID, expiry). This makes horizontal
    scaling trivial.
  - The trade-off: tokens can't be invalidated before they expire. For V0.1,
    this is acceptable. In production, you'd add a token blacklist or use
    short-lived access tokens + refresh tokens.
  - We sign with HS256 (HMAC-SHA256) — a symmetric algorithm. Both signing
    and verification use the same SECRET_KEY, which is fine since they both
    happen in this same service.
"""

from datetime import datetime, timedelta
from typing import Optional

import bcrypt
from jose import JWTError, jwt

from app.config import get_settings

settings = get_settings()


def hash_password(plain_password: str) -> str:
    """
    Converts a plain-text password into a bcrypt hash.
    
    bcrypt.hashpw() requires bytes, not a string, so we encode first.
    gensalt() generates a random salt and embeds the cost factor (default=12)
    directly into the resulting hash string — so we never need to store
    the salt separately. It's all in the hash.
    """
    password_bytes = plain_password.encode("utf-8")
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    # Decode back to a string for storage in PostgreSQL VARCHAR column
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verifies a plain-text password against a stored bcrypt hash.
    
    bcrypt.checkpw() is a constant-time comparison — it always takes
    roughly the same amount of time regardless of whether the password
    matches or not. This prevents timing attacks where an attacker could
    measure response time to guess how many characters they got right.
    """
    password_bytes = plain_password.encode("utf-8")
    hashed_bytes = hashed_password.encode("utf-8")
    return bcrypt.checkpw(password_bytes, hashed_bytes)


def create_access_token(
    subject: str, expires_delta: Optional[timedelta] = None
) -> str:
    """
    Creates a signed JWT token identifying a user by their UUID.
    The 'sub' (subject) claim holds the user's UUID string.
    The 'exp' (expiry) claim defaults to ACCESS_TOKEN_EXPIRE_MINUTES.

    `expires_delta` overrides the default — used by the web cookie flow,
    which needs a longer lifetime than the mobile access token because
    web sessions don't have refresh-token support.
    """
    if expires_delta is None:
        expires_delta = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    expire = datetime.utcnow() + expires_delta
    payload = {
        "sub": subject,
        "exp": expire,
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_access_token(token: str) -> Optional[str]:
    """
    Decodes and validates a JWT, returning the user UUID string (subject).
    Returns None if the token is expired, tampered with, or malformed.
    """
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        subject: str = payload.get("sub")
        return subject if subject else None
    except JWTError:
        return None


# Valid `iss` values for a Google-issued ID token (both forms occur in the wild).
_GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


def verify_google_id_token(id_token_str: str) -> dict:
    """
    Verify a Google ID token and return its decoded claims dict.

    google-auth fetches Google's public keys and checks the RS256 signature,
    issuer, and expiry. We then enforce the audience against our own configured
    client IDs. Raises ValueError on ANY failure (bad signature/expiry/issuer/
    audience) — callers treat that as an authentication failure (401).

    Imported lazily so this module still imports where google-auth is absent
    (e.g. the SQLite test suite, which monkeypatches this function).
    """
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests

    # audience=None: we accept several client ids (web + iOS), and
    # verify_oauth2_token only takes a single audience — so we check `aud`
    # ourselves below against the allowed set.
    claims = google_id_token.verify_oauth2_token(
        id_token_str, google_requests.Request()
    )

    allowed = get_settings().google_client_ids
    if not allowed or claims.get("aud") not in allowed:
        # aud must equal one of our OAuth client ids — blocks a token minted
        # for a different app from authenticating against ours.
        raise ValueError("invalid_audience")

    if claims.get("iss") not in _GOOGLE_ISSUERS:
        raise ValueError("invalid_issuer")

    return claims