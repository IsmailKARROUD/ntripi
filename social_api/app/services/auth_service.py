"""
services/auth_service.py — Shared business logic for user authentication.

Both the JSON API (routers/auth.py) and the web form flow (routers/web.py)
call these functions. Keeps password hashing, JWT creation, and DB logic
in one place — no duplication across routes.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select, or_
from sqlalchemy.orm import Session

from app.models.user import User
from app.services.auth import create_access_token, hash_password, verify_password
from app.validators.username import (
    validate_username,
    normalize_username,
    validate_display_name,
    generate_username_from,
)

# Precomputed bcrypt hash used when the login identifier doesn't exist.
# Always calling verify_password (even against this dummy hash) ensures
# the response time is identical whether the identifier is wrong or the
# password is wrong — preventing timing-based user enumeration.
_DUMMY_HASH = hash_password("dummy_timing_placeholder_password1")


class AuthError(Exception):
    def __init__(self, message: str, http_status: int = 400) -> None:
        self.message = message
        self.http_status = http_status
        super().__init__(message)


def authenticate_user(identifier: str, password: str, db: Session) -> tuple[User, str]:
    """
    Validate credentials and return (user, JWT token) on success.
    Accepts either an email address or a username (case-insensitive).
    Raises AuthError on any failure.
    """
    identifier = identifier.strip().lower()

    user = db.execute(
        select(User).where(
            or_(
                User.email == identifier,
                User.username_lower == identifier,
            )
        )
    ).scalar_one_or_none()

    password_matches = verify_password(
        password,
        # Google-only accounts have no password_hash — fall back to the dummy
        # so we stay timing-safe and password login fails cleanly (without
        # leaking that the account exists as a Google account).
        user.password_hash if (user and user.password_hash) else _DUMMY_HASH,
    )

    if not user or not password_matches:
        raise AuthError("Incorrect email/username or password.", http_status=401)

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

    # Defense-in-depth: validate even though Pydantic schema already checked.
    try:
        username = validate_username(username)
    except ValueError as exc:
        raise AuthError(str(exc), http_status=422)

    username_lower = normalize_username(username)
    email = email.strip().lower()

    try:
        display_name = validate_display_name(display_name)
    except ValueError as exc:
        raise AuthError(str(exc), http_status=422)

    existing_username = db.execute(
        select(User).where(User.username_lower == username_lower)
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
        username_lower=username_lower,
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


def login_or_register_google(
    google_sub: str,
    email: str,
    email_verified: bool,
    name: str | None,
    picture: str | None,
    tos_accepted: bool,
    db: Session,
) -> tuple[User, str]:
    """
    Resolve a verified Google identity to a Ntripi account, returning
    (user, JWT token). Order: match the stable google_sub, else link a
    Google-verified email to an existing account, else create a new account.
    Raises AuthError on failure. The caller (routers/auth.py) issues the
    refresh token and commits again, mirroring create_user/authenticate_user.
    """
    email = (email or "").strip().lower()
    if not email:
        raise AuthError("Google account has no email.", http_status=400)

    # 1. Returning Google user — keyed on the stable `sub`, never the email.
    user = db.execute(
        select(User).where(User.google_sub == google_sub)
    ).scalar_one_or_none()
    if user:
        if not user.is_active:
            raise AuthError("Your account has been deactivated.", http_status=403)
        if email_verified and not user.email_verified:
            user.email_verified = True
        db.commit()
        db.refresh(user)
        return user, create_access_token(subject=str(user.id))

    # 2. An account already exists on this email — link Google to it.
    existing = db.execute(
        select(User).where(User.email == email)
    ).scalar_one_or_none()
    if existing:
        if not existing.is_active:
            raise AuthError("Your account has been deactivated.", http_status=403)
        if not email_verified:
            # Only link/verify on a Google-verified email — an unverified Google
            # email could be attacker-controlled and must not claim an account.
            raise AuthError(
                "This email is already registered. Sign in with your password.",
                http_status=409,
            )
        existing.google_sub = google_sub  # keep password_hash — both methods stay valid
        existing.email_verified = True
        db.commit()
        db.refresh(existing)
        return existing, create_access_token(subject=str(existing.id))

    # 3. Brand-new account from the Google profile.
    if not tos_accepted:
        raise AuthError(
            "You must accept the Terms of Service to register.",
            http_status=400,
        )

    username = generate_username_from(
        email,
        is_taken=lambda lo: db.execute(
            select(User).where(User.username_lower == lo)
        ).scalar_one_or_none()
        is not None,
    )

    display_name = None
    if name:
        try:
            display_name = validate_display_name(name.strip()[:50])
        except ValueError:
            display_name = None  # unusual Google name — drop rather than fail signup

    new_user = User(
        username=username,
        username_lower=normalize_username(username),
        email=email,
        password_hash=None,  # Google-only account — no password
        google_sub=google_sub,
        email_verified=bool(email_verified),
        display_name=display_name,
        avatar_url=picture,
        tos_accepted_at=datetime.now(timezone.utc),
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user, create_access_token(subject=str(new_user.id))
