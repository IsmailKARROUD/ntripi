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