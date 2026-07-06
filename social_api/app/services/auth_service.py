"""
services/auth_service.py — Shared business logic for user authentication.

Both the JSON API (routers/auth.py) and the web form flow (routers/web.py)
call these functions. Keeps password hashing, JWT creation, and DB logic
in one place — no duplication across routes.
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta

from sqlalchemy import select, or_
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models.user import User
from app.models.password_history import PasswordHistory
from app.models.security_audit_log import SecurityAuditLog
from app.services import (
    email_service,
    email_token_service,
    pwned_service,
    refresh_token_service,
)
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
    def __init__(
        self, message: str, http_status: int = 400, code: str = "auth_error"
    ) -> None:
        self.message = message
        self.http_status = http_status
        self.code = code
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
        raise AuthError(
            "Incorrect email/username or password.",
            http_status=401,
            code="login_invalid",
        )

    if not user.is_active:
        raise AuthError(
            "Your account has been deactivated.",
            http_status=403,
            code="account_deactivated",
        )

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
            code="tos_required",
        )

    # Defense-in-depth: validate even though Pydantic schema already checked.
    try:
        username = validate_username(username)
    except ValueError as exc:
        raise AuthError(str(exc), http_status=422, code="username_invalid")

    username_lower = normalize_username(username)
    email = email.strip().lower()

    try:
        display_name = validate_display_name(display_name)
    except ValueError as exc:
        raise AuthError(str(exc), http_status=422, code="display_name_invalid")

    existing_username = db.execute(
        select(User).where(User.username_lower == username_lower)
    ).scalar_one_or_none()
    if existing_username:
        raise AuthError(
            "This username is already taken.",
            http_status=409,
            code="username_taken",
        )

    existing_email = db.execute(
        select(User).where(User.email == email)
    ).scalar_one_or_none()
    if existing_email:
        raise AuthError(
            "An account with this email already exists.",
            http_status=409,
            code="email_taken",
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

    _record_password_history(db, new_user.id, new_user.password_hash)
    db.commit()

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


# ---------------------------------------------------------------------------
# Password reset + email verification (emailed single-use links)
# ---------------------------------------------------------------------------

_PASSWORD_RESET_TTL = timedelta(minutes=30)
_EMAIL_VERIFY_TTL = timedelta(hours=24)

# How many past passwords (including the current one) a user may not reuse.
_PASSWORD_HISTORY_KEEP = 5


def _email_html(heading: str, body: str, button_label: str, link: str) -> str:
    """Minimal branded HTML email body shared by both flows."""
    return f"""\
<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1b2a22">
  <h2 style="color:#1F5E3A;margin:0 0 12px">Ntripi</h2>
  <h3 style="margin:0 0 8px">{heading}</h3>
  <p style="color:#52615a;font-size:14px;margin:0 0 20px">{body}</p>
  <a href="{link}" style="display:inline-block;background:#1F5E3A;color:#fff;
     text-decoration:none;font-weight:700;padding:12px 22px;border-radius:50px">{button_label}</a>
  <p style="color:#8a9690;font-size:12px;margin:24px 0 0">
    If the button doesn't work, paste this link into your browser:<br>{link}
  </p>
</div>"""


def send_password_reset(db: Session, email: str) -> None:
    """
    Email a password-reset link if a password account exists for `email`.
    No-op (silently) otherwise — callers must NOT reveal whether the address
    exists (enumeration-safe).
    """
    email = (email or "").strip().lower()
    user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    # Only password accounts can reset a password; Google-only accounts have none.
    if user is None or not user.password_hash or not user.is_active:
        return

    raw = email_token_service.issue(
        db, user.id, email_token_service.PURPOSE_PASSWORD_RESET, _PASSWORD_RESET_TTL
    )
    db.commit()

    link = f"{get_settings().share_base_url}/reset-password?token={raw}"
    email_service.send_email(
        to=user.email,
        subject="Reset your Ntripi password",
        html=_email_html(
            "Reset your password",
            "We received a request to reset your password. This link expires in 30 minutes.",
            "Reset password",
            link,
        ),
    )


def reset_password(db: Session, token: str, new_password: str) -> None:
    """Consume a reset token, set the new password, and revoke all the user's
    refresh tokens (log out everywhere). Raises AuthError on a bad/expired token."""
    try:
        user_id = email_token_service.consume(
            db, token, email_token_service.PURPOSE_PASSWORD_RESET
        )
    except email_token_service.InvalidTokenError:
        raise AuthError("This reset link is invalid or has expired.", http_status=400)

    user = db.get(User, user_id)
    if user is None:
        raise AuthError("This reset link is invalid or has expired.", http_status=400)

    user.password_hash = hash_password(new_password)
    _record_password_history(db, user.id, user.password_hash)
    refresh_token_service.revoke_all_for_user(db, user.id)
    db.commit()


# ---------------------------------------------------------------------------
# Password change (authenticated, in-app) + supporting helpers
# ---------------------------------------------------------------------------


def _record_password_history(db: Session, user_id, password_hash: str) -> None:
    """Append a password hash to the user's history and prune to the newest N,
    so the reuse check stays bounded (bcrypt is deliberately slow)."""
    db.add(PasswordHistory(user_id=user_id, password_hash=password_hash))
    db.flush()
    rows = (
        db.execute(
            select(PasswordHistory)
            .where(PasswordHistory.user_id == user_id)
            .order_by(PasswordHistory.created_at.desc(), PasswordHistory.id.desc())
        )
        .scalars()
        .all()
    )
    for stale in rows[_PASSWORD_HISTORY_KEEP:]:
        db.delete(stale)


def _password_recently_used(db: Session, user: User, new_password: str) -> bool:
    """True if new_password matches the current password or a recent historical
    one — checked with bcrypt against each retained hash."""
    hashes = {user.password_hash} if user.password_hash else set()
    hashes.update(
        row.password_hash
        for row in db.execute(
            select(PasswordHistory)
            .where(PasswordHistory.user_id == user.id)
            .order_by(PasswordHistory.created_at.desc(), PasswordHistory.id.desc())
            .limit(_PASSWORD_HISTORY_KEEP)
        ).scalars()
    )
    return any(verify_password(new_password, h) for h in hashes)


def _record_security_event(
    db: Session, user_id, event_type: str, ip: str | None, user_agent: str | None
) -> None:
    """Append a row to the security audit trail. Never stores secrets."""
    db.add(
        SecurityAuditLog(
            user_id=user_id,
            event_type=event_type,
            ip_address=(ip or "")[:64] or None,
            user_agent=(user_agent or "")[:255] or None,
        )
    )


def _send_password_changed_email(user: User) -> None:
    """Confirmation email with a 'not you?' fast track to the reset flow."""
    # Hash deep-link into the Flutter web app (served at /app/, hash routing) —
    # a bare /forgot-password is served by neither the backend nor the SPA.
    link = f"{get_settings().share_base_url}/app/#/forgot-password"
    email_service.send_email(
        to=user.email,
        subject="Your Ntripi password was changed",
        html=_email_html(
            "Your password was changed",
            "Your Ntripi password was just changed and every other device was "
            "signed out. If this wasn't you, secure your account now by resetting "
            "your password.",
            "Secure your account",
            link,
        ),
    )


def change_password(
    db: Session,
    user: User,
    current_password: str,
    new_password: str,
    *,
    ip: str | None = None,
    user_agent: str | None = None,
) -> None:
    """Change the signed-in user's password.

    Verifies the current password, blocks reuse of a recent password and any
    known-breached one, revokes every session, writes an audit row, and emails
    a confirmation. All other devices are logged out; the caller reissues this
    device's tokens. Raises AuthError on any failure."""
    if not user.password_hash:
        # Google-only account — nothing to change. The UI hides this; guard anyway.
        raise AuthError("This account has no password set.", http_status=400)

    if not verify_password(current_password, user.password_hash):
        _record_security_event(db, user.id, "password_change_failed", ip, user_agent)
        db.commit()
        # 403 (not 401): the session is valid — only the re-auth check failed.
        # The Flutter AuthInterceptor treats any 401 as session-dead and redirects
        # to /login, which would kick the user off the change-password screen.
        raise AuthError("Your current password is incorrect.", http_status=403)

    if _password_recently_used(db, user, new_password):
        raise AuthError(
            "You can't reuse a recent password. Choose a new one.", http_status=400
        )

    if pwned_service.is_pwned(new_password):
        raise AuthError(
            "This password appeared in a data breach. Choose a different one.",
            http_status=400,
        )

    user.password_hash = hash_password(new_password)
    _record_password_history(db, user.id, user.password_hash)
    refresh_token_service.revoke_all_for_user(db, user.id)
    _record_security_event(db, user.id, "password_change", ip, user_agent)
    db.commit()

    # Best-effort — a mail outage must not fail the change the user completed.
    try:
        _send_password_changed_email(user)
    except Exception:
        pass


def send_email_verification(db: Session, user: User) -> None:
    """Issue an email-verification token and email the link. Best-effort —
    callers wrap this so a send failure never breaks registration."""
    if user.email_verified:
        return
    raw = email_token_service.issue(
        db, user.id, email_token_service.PURPOSE_EMAIL_VERIFY, _EMAIL_VERIFY_TTL
    )
    db.commit()

    link = f"{get_settings().share_base_url}/verify-email?token={raw}"
    email_service.send_email(
        to=user.email,
        subject="Verify your email — Ntripi",
        html=_email_html(
            "Verify your email",
            "Confirm your email address to unlock creating trips, rating, and following people.",
            "Verify email",
            link,
        ),
    )


def verify_email(db: Session, token: str) -> User:
    """Consume a verification token and mark the user's email verified.
    Returns the user. Raises AuthError on a bad/expired token."""
    try:
        user_id = email_token_service.consume(
            db, token, email_token_service.PURPOSE_EMAIL_VERIFY
        )
    except email_token_service.InvalidTokenError:
        raise AuthError("This verification link is invalid or has expired.", http_status=400)

    user = db.get(User, user_id)
    if user is None:
        raise AuthError("This verification link is invalid or has expired.", http_status=400)

    user.email_verified = True
    db.commit()
    return user
