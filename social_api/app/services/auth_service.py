"""
services/auth_service.py — Shared business logic for user authentication.

Both the JSON API (routers/auth.py) and the web form flow (routers/web.py)
call these functions. Keeps password hashing, JWT creation, and DB logic
in one place — no duplication across routes.

AuthError carries an HTTP status code so the API router can map it to the
right HTTPException, while the web router can use the message directly for
form error rendering.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user import User
from app.services.auth import create_access_token, hash_password, verify_password

# Precomputed bcrypt hash used when the login email doesn't exist.
# Always calling verify_password (even against this dummy hash) ensures
# the response time is identical whether the email is wrong or the password
# is wrong — preventing timing-based user enumeration.
_DUMMY_HASH = hash_password("dummy_timing_placeholder_password1")


class AuthError(Exception):
    def __init__(self, message: str, http_status: int = 400) -> None:
        self.message = message
        self.http_status = http_status
        super().__init__(message)


def authenticate_user(email: str, password: str, db: Session) -> tuple[User, str]:
    """
    Validate credentials and return (user, JWT token) on success.
    Raises AuthError on any failure.
    """
    user = db.execute(
        select(User).where(User.email == email)
    ).scalar_one_or_none()

    password_matches = verify_password(
        password,
        user.password_hash if user else _DUMMY_HASH,
    )

    if not user or not password_matches:
        raise AuthError("Incorrect email or password.", http_status=401)

    if not user.is_active:
        raise AuthError("Your account has been deactivated.", http_status=403)

    token = create_access_token(subject=str(user.id))
    return user, token


def create_user(
    username: str,
    email: str,
    password: str,
    display_name: str | None,
    tos_accepted: bool,
    db: Session,
) -> tuple[User, str]:
    """
    Create a new user account and return (user, JWT token) on success.
    Raises AuthError on any failure (ToS not accepted, duplicates, etc.).
    """
    if not tos_accepted:
        raise AuthError(
            "You must accept the Terms of Service to register.",
            http_status=400,
        )

    existing_username = db.execute(
        select(User).where(User.username == username)
    ).scalar_one_or_none()
    if existing_username:
        raise AuthError("This username is already taken.", http_status=409)

    existing_email = db.execute(
        select(User).where(User.email == email)
    ).scalar_one_or_none()
    if existing_email:
        raise AuthError(
            "An account with this email already exists.", http_status=409
        )

    new_user = User(
        username=username,
        email=email,
        password_hash=hash_password(password),
        display_name=display_name,
        tos_accepted_at=datetime.now(timezone.utc),
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    token = create_access_token(subject=str(new_user.id))
    return new_user, token
