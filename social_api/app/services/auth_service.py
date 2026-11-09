"""
services/auth_service.py — Shared business logic for user authentication.

Both the JSON API (routers/auth.py) and the web form flow (routers/web.py)
call these functions. Keeps password hashing, JWT creation, and DB logic
in one place — no duplication across routes.
"""

from __future__ import annotations

from datetime import date, datetime, timezone, timedelta

from sqlalchemy import select, or_
from sqlalchemy.orm import Session

from app.config import get_settings
from app.constants.tos import TOS_VERSION
from app.models.user import User
from app.models.password_history import PasswordHistory
from app.models.security_audit_log import SecurityAuditLog
from app.services import (
    account_service,
    email_service,
    email_token_service,
    google_avatar,
    google_people,
    pwned_service,
    refresh_token_service,
    text_moderation_service,
)
from app.services.age_service import MINIMUM_AGE, is_old_enough
from app.services.auth import create_access_token, hash_password, verify_password
from app.validators.links import find_link
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


# The refusal for an address blocked after a suspended account was erased.
# Deliberately says nothing about why: anyone can type any address at sign-up.
EMAIL_UNAVAILABLE = "This email address can't be used to create an account."


def create_user(
    username: str,
    email: str,
    password: str,
    display_name: str | None,
    tos_accepted: bool,
    date_of_birth: date,
    db: Session,
    dob_source: str = "self",
) -> tuple[User, str]:
    """
    Create a new user account and return (user, JWT token) on success.
    Raises AuthError on any failure (ToS not accepted, underage, duplicates).
    """
    if not tos_accepted:
        raise AuthError(
            "You must accept the Terms of Service to register.",
            http_status=400,
            code="tos_required",
        )

    # Defense-in-depth, exactly like the tos_accepted re-check above: this
    # function commits, so an age failure discovered by a caller afterwards
    # could not undo the account.
    if not is_old_enough(date_of_birth):
        raise AuthError(
            f"You must be at least {MINIMUM_AGE} years old to use Ntripi.",
            http_status=400,
            code="underage",
        )

    # Defense-in-depth: validate even though Pydantic schema already checked.
    try:
        username = validate_username(username)
    except ValueError as exc:
        raise AuthError(str(exc), http_status=422, code="username_invalid")

    username_lower = normalize_username(username)
    email = email.strip().lower()

    # Re-checked here, like the age gate above: this function commits.
    if account_service.is_signup_blocked(db, email):
        raise AuthError(EMAIL_UNAVAILABLE, http_status=400, code="email_unavailable")

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
        date_of_birth=date_of_birth,
        dob_source=dob_source,
        tos_accepted_at=datetime.now(timezone.utc),
        # Record WHICH revision was accepted — "they agreed to the terms"
        # is unprovable once the terms change.
        tos_accepted_version=TOS_VERSION,
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
    date_of_birth: date | None = None,
    google_access_token: str | None = None,
) -> tuple[User, str]:
    """
    Resolve a verified Google identity to a Ntripi account, returning
    (user, JWT token). Order: match the stable google_sub, else link a
    Google-verified email to an existing account, else create a new account.
    Raises AuthError on failure. The caller (routers/auth.py) issues the
    refresh token and commits again, mirroring create_user/authenticate_user.

    `date_of_birth` and `google_access_token` are read by the create-a-new-
    account branch ONLY, exactly like `tos_accepted` — signing in and linking
    must never demand either, or every returning Google user would be
    re-prompted at every sign-in.
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
            # Same code as the password path — the client keys off it to route a
            # suspended user to the appeal screen instead of a dead-end error.
            raise AuthError(
                "Your account has been deactivated.",
                http_status=403,
                code="account_deactivated",
            )
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
            raise AuthError(
                "Your account has been deactivated.",
                http_status=403,
                code="account_deactivated",
            )
        if not email_verified:
            # Only link/verify on a Google-verified email — an unverified Google
            # email could be attacker-controlled and must not claim an account.
            raise AuthError(
                "This email is already registered. Sign in with your password.",
                http_status=409,
            )
        if not existing.email_verified:
            # Nobody ever proved they own this address — registration needs no
            # verification, so the password may be an attacker's who signed up on
            # the victim's email first. Google has just proved ownership: lock
            # that password and its sessions out rather than hand them the
            # account the moment the real owner signs in.
            existing.password_hash = None
            refresh_token_service.revoke_all_for_user(db, existing.id)
            _record_security_event(
                db, existing.id, "unverified_password_dropped_on_google_link",
                None, None,
            )
        # A verified account keeps its password — both methods stay valid.
        existing.google_sub = google_sub
        existing.email_verified = True
        db.commit()
        db.refresh(existing)
        return existing, create_access_token(subject=str(existing.id))

    # 3. Brand-new account from the Google profile.
    # A blocked address (an erased suspended account's) is refused first. Ahead
    # of the ToS gate, because the client's first post never carries
    # tos_accepted: checked after it, this person would be walked through the
    # consent sheet and the birthday scope only to be refused at the end.
    if account_service.is_signup_blocked(db, email):
        raise AuthError(EMAIL_UNAVAILABLE, http_status=400, code="email_unavailable")

    if not tos_accepted:
        raise AuthError(
            "You must accept the Terms of Service to register.",
            http_status=400,
            code="tos_required",  # same code as the password path — clients key off it
        )

    # Google first, the user's own answer second. The People API result is the
    # more reliable of the two — it is Google's own record rather than a number
    # typed into our form — so it wins whenever it is usable, and the client's
    # posted date is the fallback for the many accounts with no birthday, a
    # hidden year, or a declined scope.
    dob, dob_source = date_of_birth, "self"
    if google_access_token:
        from_google = google_people.fetch_birthdate(google_access_token, google_sub)
        if from_google is not None:
            dob, dob_source = from_google, "google"

    if dob is None:
        raise AuthError(
            "A date of birth is required to create an account.",
            http_status=400,
            code="dob_required",
        )
    if not is_old_enough(dob):
        raise AuthError(
            f"You must be at least {MINIMUM_AGE} years old to use Ntripi.",
            http_status=400,
            code="underage",
        )

    def is_taken(lowered: str) -> bool:
        return db.execute(
            select(User).where(User.username_lower == lowered)
        ).scalar_one_or_none() is not None

    username = _google_username(email, is_taken)

    display_name = None
    if name:
        try:
            display_name = validate_display_name(name.strip()[:50])
        except ValueError:
            display_name = None  # unusual Google name — drop rather than fail signup
    if display_name and find_link(display_name) is not None:
        display_name = None  # the link rule, as at registration; settable later

    # Scan the username and the Google profile name, but never let either refuse
    # the signup: neither was typed here (one comes from the e-mail address, the
    # other from Google), so a 422 would lock a real person out with no way to
    # fix it. One request for both. On a reject the name is dropped — it can be
    # set again on the profile — and the username, which can never be changed,
    # is kept only if it passes alone; otherwise it is the fallback an unusable
    # address already gets (traveler, traveler1, …). The decision rows are the
    # record.
    scans = [_scan_google_profile({"username": username, "display_name": display_name}, db)]
    if not scans[-1][1] and display_name is not None:
        display_name = None
        scans.append(_scan_google_profile({"username": username}, db))
    ctx, kept = scans[-1]
    if not kept:
        username = generate_username_from("", is_taken)
        # Nothing offensive is stored, so the profile itself is clean —
        # flagging it would hide a bio that never existed.
        ctx.status = "approved"

    new_user = User(
        username=username,
        username_lower=normalize_username(username),
        email=email,
        password_hash=None,  # Google-only account — no password
        google_sub=google_sub,
        email_verified=bool(email_verified),
        display_name=display_name,
        avatar_url=None,  # Google's photo is copied in below, never linked to
        date_of_birth=dob,
        dob_source=dob_source,
        moderation_status=ctx.status,
        tos_accepted_at=datetime.now(timezone.utc),
        # Record WHICH revision was accepted — "they agreed to the terms"
        # is unprovable once the terms change.
        tos_accepted_version=TOS_VERSION,
    )
    db.add(new_user)
    db.flush()
    for scan, _ in scans:
        text_moderation_service.attach_target(scan, new_user.id)
    # Lazy: moderation_actions pulls in admin_service, which imports this module.
    from app.services import moderation_actions

    moderation_actions.escalate_if_flagged(
        db, "user", new_user, escalate_flag=ctx.escalate, decision_id=ctx.decision_id,
    )
    db.commit()
    db.refresh(new_user)

    # After the account's commit: a refused photo commits the session for its
    # audit row. Copied like an upload, or no photo at all (google_avatar.py).
    avatar_url = google_avatar.copy_photo_from_worker(db, new_user, picture)
    if avatar_url is not None:
        new_user.avatar_url = avatar_url
        db.commit()
        db.refresh(new_user)
    return new_user, create_access_token(subject=str(new_user.id))


def _google_username(email: str, is_taken) -> str:
    """A Google sign-up's username, from the e-mail address's local part — held
    to the link rule like one typed at registration (validators/links.py): a
    local part such as `anna.paris` is a site name, so its dots become
    underscores, which no site name can hold (`anna_paris`)."""
    username = generate_username_from(email, is_taken=is_taken)
    if find_link(username) is None:
        return username
    local_part = email.split("@", 1)[0]
    return generate_username_from(local_part.replace(".", "_"), is_taken=is_taken)


def _scan_google_profile(
    fields: dict[str, str | None], db: Session,
) -> tuple[text_moderation_service.TextModerationContext, bool]:
    """Scan text a Google sign-up did not type: its context, and False on a
    reject — the caller drops the text instead of refusing the account."""
    ctx = text_moderation_service.TextModerationContext(
        db=db, settings=get_settings(), target_type="user", author=None,
    )
    try:
        text_moderation_service.moderate_fields_or_raise(fields, ctx)
    except text_moderation_service.TextModerationRejectedError:
        return ctx, False
    return ctx, True


# ---------------------------------------------------------------------------
# Password reset + email verification (emailed single-use links)
# ---------------------------------------------------------------------------

_PASSWORD_RESET_TTL = timedelta(minutes=30)
_EMAIL_VERIFY_TTL = timedelta(hours=24)

# How many past passwords (including the current one) a user may not reuse.
_PASSWORD_HISTORY_KEEP = 5


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
        html=email_service.branded_email_html(
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
    email_token_service.retire_unused(
        db, user.id, email_token_service.PURPOSE_PASSWORD_RESET
    )
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
        html=email_service.branded_email_html(
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
    email_token_service.retire_unused(
        db, user.id, email_token_service.PURPOSE_PASSWORD_RESET
    )
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
        html=email_service.branded_email_html(
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
