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

from datetime import datetime, timedelta, timezone
from typing import Any

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import get_settings

settings = get_settings()

# CryptContext manages the hashing algorithm(s).
# schemes=["bcrypt"] means we only use bcrypt.
# deprecated="auto" means if we ever add a new algorithm, old hashes
# (using the previous algorithm) are still verified correctly.
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# A precomputed dummy hash used in constant-time login comparisons.
# See verify_password_dummy() below.
DUMMY_HASH = pwd_context.hash("dummy_password_for_timing_attack_prevention")


def hash_password(plain_password: str) -> str:
    """
    Hash a plain-text password using bcrypt.
    The result is safe to store in the database.
    """
    return pwd_context.hash(plain_password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a plain password against a stored bcrypt hash.
    Returns True if they match, False otherwise.
    This function takes constant time regardless of whether the hash matches,
    which prevents timing side-channel attacks.
    """
    return pwd_context.verify(plain_password, hashed_password)


def verify_password_against_dummy(plain_password: str) -> bool:
    """
    Run a bcrypt verification against a precomputed dummy hash.

    WHY: Timing attack prevention in login.
    If the login endpoint returns immediately when the email is not found
    (skipping the bcrypt verify), an attacker can distinguish "user does
    not exist" from "wrong password" by measuring response time. With bcrypt's
    intentional slowness, this difference would be hundreds of milliseconds.
    By always calling bcrypt.verify (even for non-existent users), both
    code paths take the same amount of time. The result is always False.
    """
    return pwd_context.verify(plain_password, DUMMY_HASH)


def create_access_token(subject: str) -> str:
    """
    Create a signed JWT access token.

    Args:
        subject: The user's UUID as a string. This becomes the 'sub' claim.

    Returns:
        A signed JWT string to be sent to the client.

    Token payload:
        sub: user UUID string (the "subject" of the token)
        exp: expiry timestamp (UTC)
        iat: issued-at timestamp (UTC)
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    payload: dict[str, Any] = {
        "sub": subject,
        "exp": expire,
        "iat": now,
    }

    # jose.jwt.encode signs the payload with our secret key.
    # The result is a base64url-encoded string: header.payload.signature
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any]:
    """
    Decode and validate a JWT token.

    Raises:
        JWTError: if the token is invalid, expired, or has a bad signature.

    Returns:
        The decoded payload dict (containing 'sub', 'exp', 'iat').
    """
    # jose automatically validates the signature and expiry.
    # If the token is expired or tampered with, JWTError is raised.
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
