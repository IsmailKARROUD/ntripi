"""
routers/auth.py — Authentication endpoints.

Route prefix: /auth

Endpoints:
  POST /auth/register → create account, returns TokenPair.
  POST /auth/login    → log in with identifier + password, returns TokenPair.
  POST /auth/refresh  → exchange a refresh token for a new TokenPair (rotates).
  POST /auth/logout   → revoke a refresh token. Always returns 204.
  GET  /auth/tos      → current Terms, Guidelines and Privacy Policy (?lang=).
  POST /auth/accept-tos → record acceptance of the current TOS_VERSION.

OAuth 2.0 refresh-token pattern: a short-lived JWT access token (15 min)
is paired with a long-lived opaque refresh token (30 days, rotating).
The refresh token is stored server-side (hashed) so it can be revoked.
Login / register / refresh all flow through this router; the rotation
chain and theft detection live in services/refresh_token_service.py.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session
from starlette.requests import Request

from app.config import Settings, get_settings
from app.constants.guidelines import (
    GUIDELINES_DATE,
    GUIDELINES_VERSION,
    get_guidelines,
)
from app.constants.privacy import PRIVACY_DATE, PRIVACY_VERSION, get_privacy
from app.constants.tos import TOS_DATE, TOS_VERSION, get_tos
from app.database import get_db
from app.dependencies import get_current_user
from app.i18n import resolve_lang, translator
from app.limiter import limiter
from app.models.user import User
from app.schemas.auth import (
    AcceptTosRequest,
    ChangePasswordRequest,
    ForgotPasswordRequest,
    GoogleAuthRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
)
from app.schemas.user import UserPrivateProfile
from app.services import auth_service, refresh_token_service
from app.services.age_service import MINIMUM_AGE, is_old_enough
from app.services.auth import create_access_token, verify_google_id_token
from app.services.moderation_actions import escalate_if_flagged
from app.services.text_moderation_service import attach_target, moderate_or_422
from app.errors import ApiError

router = APIRouter(prefix="/auth", tags=["Authentication"])


def _token_pair(
    user, access_token: str, refresh_token: str, refresh_row
) -> TokenPair:
    return TokenPair(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=str(user.id),
        username=user.username,
        refresh_expires_at=refresh_row.expires_at,
    )


@router.post(
    "/register",
    response_model=TokenPair,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new account",
)
@limiter.limit("5/hour")
def register(
    request: Request,
    payload: RegisterRequest,
    db: Session = Depends(get_db),
) -> TokenPair:
    # Gated before moderate_or_422, not just inside create_user: a client that
    # omits the flag would otherwise spend a paid provider call to earn its 400.
    if not payload.tos_accepted:
        raise ApiError(
            status_code=400,
            code="tos_required",
            detail="You must accept the Terms of Service to register.",
        )

    # Gated here for the same reason as tos_required above: an underage signup
    # must not spend a paid moderation call to earn its 400.
    if not is_old_enough(payload.date_of_birth):
        raise ApiError(
            status_code=400,
            code="underage",
            detail=f"You must be at least {MINIMUM_AGE} years old to use Ntripi.",
        )

    # Scanned BEFORE create_user, never after: create_user commits, so a
    # rejection discovered afterwards could not undo the account it just made.
    # Both fields go in one dict so they cost a single provider call.
    ctx = moderate_or_422(
        db, get_settings(),
        target_type="user",
        author=None,  # the account does not exist yet
        fields={"username": payload.username, "display_name": payload.display_name},
    )

    try:
        user, access_token = auth_service.create_user(
            username=payload.username,
            email=payload.email,
            password=payload.password,
            display_name=payload.display_name,
            tos_accepted=payload.tos_accepted,
            date_of_birth=payload.date_of_birth,
            db=db,
        )
    except auth_service.AuthError as e:
        raise ApiError(status_code=e.http_status, code=e.code, detail=e.message)

    # Assigned, not escalated, matching PATCH /users/me: this is the account's
    # first and only text, so there is no earlier flag to preserve.
    user.moderation_status = ctx.status
    attach_target(ctx, user.id)  # create_user already committed, so the id is real
    escalate_if_flagged(
        db, "user", user, escalate_flag=ctx.escalate, decision_id=ctx.decision_id,
    )

    refresh_raw, refresh_row = refresh_token_service.issue(
        db,
        user_id=user.id,
        user_agent=request.headers.get("user-agent"),
    )
    db.commit()

    # Send the email-verification link. Best-effort — a mail outage must not
    # fail the registration the user just completed.
    try:
        auth_service.send_email_verification(db, user)
    except Exception:
        pass

    return _token_pair(user, access_token, refresh_raw, refresh_row)


@router.post(
    "/login",
    response_model=TokenPair,
    summary="Log in with email or username and password",
)
@limiter.limit("10/minute")
def login(
    request: Request,
    payload: LoginRequest,
    db: Session = Depends(get_db),
) -> TokenPair:
    try:
        user, access_token = auth_service.authenticate_user(
            payload.identifier, payload.password, db
        )
    except auth_service.AuthError as e:
        raise ApiError(status_code=e.http_status, code=e.code, detail=e.message)

    refresh_raw, refresh_row = refresh_token_service.issue(
        db,
        user_id=user.id,
        user_agent=request.headers.get("user-agent"),
    )
    db.commit()
    return _token_pair(user, access_token, refresh_raw, refresh_row)


@router.post(
    "/google",
    response_model=TokenPair,
    summary="Sign in or sign up with Google",
)
@limiter.limit("10/minute")
def google_auth(
    request: Request,
    payload: GoogleAuthRequest,
    db: Session = Depends(get_db),
) -> TokenPair:
    """
    Verify a Google ID token, then log in / link / create the matching account
    and return the same TokenPair as password login. Also Ntripi's email-
    verification path: a Google-verified email flips the account to verified.
    """
    try:
        claims = verify_google_id_token(payload.id_token)
    except Exception:
        # Any verification failure (bad signature/expiry/audience/issuer, or
        # google-auth not installed) is an auth failure — never leak details.
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="google_token_invalid", detail="Invalid Google token.",
        )

    try:
        user, access_token = auth_service.login_or_register_google(
            google_sub=claims["sub"],
            email=claims.get("email", ""),
            email_verified=bool(claims.get("email_verified", False)),
            name=claims.get("name"),
            picture=claims.get("picture"),
            tos_accepted=payload.tos_accepted,
            db=db,
            date_of_birth=payload.date_of_birth,
            google_access_token=payload.google_access_token,
        )
    except auth_service.AuthError as e:
        raise ApiError(status_code=e.http_status, code=e.code, detail=e.message)

    refresh_raw, refresh_row = refresh_token_service.issue(
        db,
        user_id=user.id,
        user_agent=request.headers.get("user-agent"),
    )
    db.commit()
    return _token_pair(user, access_token, refresh_raw, refresh_row)


@router.post(
    "/refresh",
    response_model=TokenPair,
    summary="Rotate refresh token, return new access + refresh tokens",
)
@limiter.limit("60/minute")
def refresh(
    request: Request,
    payload: RefreshRequest,
    db: Session = Depends(get_db),
) -> TokenPair:
    """
    Consume the supplied refresh token and return a fresh TokenPair. The
    old refresh token is marked revoked atomically with the issuance of
    the successor — so a replay of the old token after a successful
    refresh triggers family-wide revocation (theft detection).

    Returns 401 `invalid_grant` for unknown / expired / revoked tokens
    so the client can distinguish session-end from a transient network
    error.
    """
    try:
        new_access, new_refresh, new_row = refresh_token_service.rotate(
            db,
            raw_token=payload.refresh_token,
            user_agent=request.headers.get("user-agent"),
        )
    except refresh_token_service.InvalidGrantError:
        db.commit()  # persist any family revocation done during theft detection
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED, code="invalid_grant", detail="invalid_grant"
        )

    # Reload user for the response payload — refresh_token_service has the
    # user_id but not the full User row.
    from app.models.user import User

    user = db.get(User, new_row.user_id)
    db.commit()
    return _token_pair(user, new_access, new_refresh, new_row)


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke a refresh token",
)
def logout(
    payload: RefreshRequest,
    db: Session = Depends(get_db),
) -> Response:
    """
    Revoke the supplied refresh token. Always returns 204 — never leaks
    whether the token was valid (prevents probing).
    """
    refresh_token_service.revoke(db, raw_token=payload.refresh_token)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/forgot-password",
    summary="Request a password-reset email",
)
@limiter.limit("3/hour")
def forgot_password(
    request: Request,
    payload: ForgotPasswordRequest,
    db: Session = Depends(get_db),
) -> dict:
    """
    Email a reset link if a password account exists for this address.
    Always returns the same 200 response regardless — never reveals whether
    the email is registered (enumeration-safe).
    """
    auth_service.send_password_reset(db, payload.email)
    return {"detail": "If an account exists for that email, a reset link has been sent."}


@router.post(
    "/change-password",
    response_model=TokenPair,
    summary="Change the signed-in user's password",
)
@limiter.limit("5/hour")
def change_password(
    request: Request,
    payload: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TokenPair:
    """
    Verify the current password, set the new one, and revoke every session.
    All other devices are logged out; this device gets a fresh TokenPair so it
    stays signed in seamlessly. Rate-limited to blunt brute-forcing the current
    password. request.client.host is the real client IP (ProxyHeadersMiddleware).
    """
    try:
        auth_service.change_password(
            db,
            current_user,
            payload.current_password,
            payload.new_password,
            ip=request.client.host if request.client else None,
            user_agent=request.headers.get("user-agent"),
        )
    except auth_service.AuthError as e:
        raise ApiError(status_code=e.http_status, code=e.code, detail=e.message)

    # Sessions were just revoked — reissue this device so the user stays logged in.
    refresh_raw, refresh_row = refresh_token_service.issue(
        db,
        user_id=current_user.id,
        user_agent=request.headers.get("user-agent"),
    )
    access_token = create_access_token(subject=str(current_user.id))
    db.commit()
    return _token_pair(current_user, access_token, refresh_raw, refresh_row)


@router.post(
    "/resend-verification",
    summary="Resend the email-verification link to the current user",
)
@limiter.limit("3/hour")
def resend_verification(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    auth_service.send_email_verification(db, current_user)
    return {"detail": "Verification email sent."}


@router.get(
    "/tos",
    summary="Get the current Terms, Community Guidelines and Privacy Policy",
)
def get_legal_documents(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> dict:
    # Language comes from ?lang= / cookie / Accept-Language via the same
    # resolver the web pages use, so the in-app sheet and the browser page
    # can never disagree about which translation the user is reading.
    lang = resolve_lang(request)
    t = translator(lang)
    return {
        "lang": lang,
        "version": TOS_VERSION,
        "date": TOS_DATE,
        "summary": get_tos(lang),
        # All three documents ride one response: the signup screen makes a
        # single call and shows any of them without leaving the form.
        "guidelines": get_guidelines(lang),
        "guidelines_version": GUIDELINES_VERSION,
        "guidelines_date": GUIDELINES_DATE,
        "privacy": get_privacy(lang),
        "privacy_version": PRIVACY_VERSION,
        "privacy_date": PRIVACY_DATE,
        # Empty for English — nothing for the authoritative text to prevail over.
        "notice_terms": t("legal_notice_terms"),
        "notice_guidelines": t("legal_notice_guidelines"),
        "notice_privacy": t("legal_notice_privacy"),
        # Served here so the in-app address can never drift from the backend
        # configuration or the store listing.
        "abuse_contact": settings.ABUSE_CONTACT_EMAIL,
        "community_guidelines_url": f"{settings.share_base_url}/guidelines",
    }


@router.post(
    "/accept-tos",
    response_model=UserPrivateProfile,
    summary="Record acceptance of the current Terms of Service revision",
)
@limiter.limit("10/hour")
def accept_tos(
    request: Request,
    # Optional so a deployed client that posts no body at all still works —
    # before the age gate this endpoint took none, and 422-ing those clients
    # would lock them behind a gate they cannot satisfy.
    payload: AcceptTosRequest | None = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    """Stamp the current revision so the client gate stops blocking.

    Writes TOS_VERSION rather than echoing a client-supplied version — the
    client must not be able to claim acceptance of a document it never showed.
    A date of birth is different: only the account holder knows it, and this
    gate is where accounts predating the age gate supply theirs.
    """
    supplied_dob = payload.date_of_birth if payload else None
    if current_user.date_of_birth is None:
        if supplied_dob is None:
            raise ApiError(
                status_code=400,
                code="dob_required",
                detail="A date of birth is required to continue.",
            )
        if not is_old_enough(supplied_dob):
            # The gate stays up and their only exit is sign-out. Deactivating
            # the account on a self-declaration is a policy call this endpoint
            # deliberately does not make on its own.
            raise ApiError(
                status_code=400,
                code="underage",
                detail=f"You must be at least {MINIMUM_AGE} years old to use Ntripi.",
            )
        current_user.date_of_birth = supplied_dob
        current_user.dob_source = "self"
    # An existing date is never overwritten: it is a declaration of record, and
    # letting someone re-declare on demand would defeat the gate entirely.

    current_user.tos_accepted_at = datetime.now(timezone.utc)
    current_user.tos_accepted_version = TOS_VERSION
    db.commit()
    db.refresh(current_user)
    return current_user
