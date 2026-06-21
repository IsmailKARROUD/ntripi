"""
routers/web.py — Server-rendered marketing pages and web auth flow.

Routes:
  GET  /          → Homepage (hero + download CTAs)
  GET  /login     → Login form (redirects if already logged in)
  GET  /register  → Register form (redirects if already logged in)
  GET  /privacy   → Privacy Policy
  GET  /terms     → Terms of Service
  POST /web/login     → Validates credentials, sets cookie, redirects to /app/
  POST /web/register  → Creates account, sets cookie, redirects to /app/

/app/ is served by the StaticFiles mount in main.py (Flutter web build).

Cookie strategy:
  - Name: ntripi_session
  - HTTP-only, Secure (production only), SameSite=Lax
  - Max-Age matches the JWT expiry configured in settings
"""

from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

from fastapi import APIRouter, Cookie, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.constants.privacy import PRIVACY_CONTENT, PRIVACY_DATE
from app.constants.tos import TOS_DATE, TOS_SUMMARY, TOS_VERSION
from app.database import get_db
from app.services import auth_service
from app.services.auth import create_access_token, decode_access_token

router = APIRouter(tags=["web"])

_TEMPLATES_DIR = Path(__file__).parent.parent / "templates"
templates = Jinja2Templates(directory=str(_TEMPLATES_DIR))
templates.env.globals["current_year"] = datetime.now().year


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _is_logged_in(session_token: str | None) -> bool:
    if not session_token:
        return False
    return decode_access_token(session_token) is not None


def _issue_web_token(user_id: str, settings: Settings) -> str:
    """Web sessions have their own (longer) lifetime than the mobile access
    token — see WEB_SESSION_EXPIRE_MINUTES. The web flow has no refresh
    mechanism, so shortening this would force re-login every 15 min."""
    return create_access_token(
        subject=user_id,
        expires_delta=timedelta(minutes=settings.WEB_SESSION_EXPIRE_MINUTES),
    )


def _set_session_cookie(
    response: RedirectResponse | HTMLResponse,
    token: str,
    settings: Settings,
) -> None:
    response.set_cookie(
        key="ntripi_session",
        value=token,
        max_age=settings.WEB_SESSION_EXPIRE_MINUTES * 60,
        path="/",
        secure=not settings.DEBUG,
        httponly=True,
        samesite="lax",
    )


# ---------------------------------------------------------------------------
# Public GET pages
# ---------------------------------------------------------------------------

@router.get("/", response_class=HTMLResponse)
def homepage(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    return templates.TemplateResponse(request, "home.html", {
        "page_title": "Ntripi — Share your travel itineraries",
        "page_description": "Plan, share, and discover travel itineraries",
        "android_download_url": settings.ANDROID_DOWNLOAD_URL,
    })


@router.get("/login", response_class=HTMLResponse)
def login_page(
    request: Request,
    ntripi_session: str | None = Cookie(None),
) -> HTMLResponse:
    if _is_logged_in(ntripi_session):
        return RedirectResponse("/app/", status_code=302)
    return templates.TemplateResponse(request, "login.html", {
        "page_title": "Sign in — Ntripi",
    })


@router.get("/register", response_class=HTMLResponse)
def register_page(
    request: Request,
    ntripi_session: str | None = Cookie(None),
) -> HTMLResponse:
    if _is_logged_in(ntripi_session):
        return RedirectResponse("/app/", status_code=302)
    return templates.TemplateResponse(request, "register.html", {
        "page_title": "Create account — Ntripi",
    })


@router.get("/privacy", response_class=HTMLResponse)
def privacy_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "privacy.html", {
        "page_title": "Privacy Policy — Ntripi",
        "content": PRIVACY_CONTENT,
        "last_updated": PRIVACY_DATE,
    })


@router.get("/terms", response_class=HTMLResponse)
def terms_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "terms.html", {
        "page_title": "Terms of Service — Ntripi",
        "content": TOS_SUMMARY,
        "last_updated": TOS_DATE,
        "tos_version": TOS_VERSION,
    })


# ---------------------------------------------------------------------------
# Web auth POST handlers
# ---------------------------------------------------------------------------

@router.post("/web/login", response_class=HTMLResponse)
def web_login(
    request: Request,
    identifier: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    try:
        user, _ = auth_service.authenticate_user(identifier, password, db)
    except auth_service.AuthError as e:
        return templates.TemplateResponse(
            request,
            "login.html",
            {
                "page_title": "Sign in — Ntripi",
                "error_message": e.message,
                "identifier": identifier,
            },
            status_code=200,
        )

    # Mint a separate longer-lived JWT for the web cookie — don't reuse
    # the 15-minute mobile access token returned by authenticate_user.
    web_token = _issue_web_token(str(user.id), settings)
    response = RedirectResponse("/app/", status_code=302)
    _set_session_cookie(response, web_token, settings)
    return response


# ---------------------------------------------------------------------------
# Password reset + email verification (emailed link landing pages)
# ---------------------------------------------------------------------------

@router.get("/reset-password", response_class=HTMLResponse)
def reset_password_page(request: Request, token: str = "") -> HTMLResponse:
    return templates.TemplateResponse(request, "reset_password.html", {
        "page_title": "Reset password — Ntripi",
        "token": token,
    })


@router.post("/web/reset-password", response_class=HTMLResponse)
def web_reset_password(
    request: Request,
    token: str = Form(...),
    password: str = Form(...),
    password_confirm: str = Form(...),
    db: Session = Depends(get_db),
) -> HTMLResponse:
    def _form_error(msg: str) -> HTMLResponse:
        return templates.TemplateResponse(request, "reset_password.html", {
            "page_title": "Reset password — Ntripi",
            "token": token,
            "error_message": msg,
        }, status_code=200)

    if password != password_confirm:
        return _form_error("Passwords do not match.")
    if len(password) < 8:
        return _form_error("Password must be at least 8 characters.")
    if not any(c.isdigit() for c in password):
        return _form_error("Password must contain at least one digit.")

    try:
        auth_service.reset_password(db, token, password)
    except auth_service.AuthError as e:
        # Bad/expired token — re-showing the form won't help; show a terminal page.
        return templates.TemplateResponse(request, "token_invalid.html", {
            "page_title": "Link expired — Ntripi",
            "message": e.message,
        }, status_code=200)

    return templates.TemplateResponse(request, "reset_password_done.html", {
        "page_title": "Password updated — Ntripi",
    })


@router.get("/verify-email", response_class=HTMLResponse)
def verify_email_page(
    request: Request,
    token: str = "",
    db: Session = Depends(get_db),
) -> HTMLResponse:
    try:
        auth_service.verify_email(db, token)
    except auth_service.AuthError as e:
        return templates.TemplateResponse(request, "token_invalid.html", {
            "page_title": "Link expired — Ntripi",
            "message": e.message,
        }, status_code=200)
    return templates.TemplateResponse(request, "email_verified.html", {
        "page_title": "Email verified — Ntripi",
    })


@router.post("/web/register", response_class=HTMLResponse)
def web_register(
    request: Request,
    email: str = Form(...),
    username: str = Form(...),
    password: str = Form(...),
    password_confirm: str = Form(...),
    display_name: str = Form(""),
    tos_accepted: str | None = Form(None),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    def _error(msg: str) -> HTMLResponse:
        return templates.TemplateResponse(
            request,
            "register.html",
            {
                "page_title": "Create account — Ntripi",
                "error_message": msg,
                "email": email,
                "username": username,
                "display_name": display_name,
            },
            status_code=200,
        )

    if password != password_confirm:
        return _error("Passwords do not match.")

    if not tos_accepted:
        return _error("You must accept the Terms of Service to register.")

    if len(password) < 8:
        return _error("Password must be at least 8 characters.")

    if not any(c.isdigit() for c in password):
        return _error("Password must contain at least one digit.")

    try:
        user, _ = auth_service.create_user(
            username=username,
            email=email,
            password=password,
            display_name=display_name or None,
            tos_accepted=True,
            db=db,
        )
    except auth_service.AuthError as e:
        return _error(e.message)

    try:
        auth_service.send_email_verification(db, user)  # best-effort
    except Exception:
        pass

    web_token = _issue_web_token(str(user.id), settings)
    response = RedirectResponse("/app/", status_code=302)
    _set_session_cookie(response, web_token, settings)
    return response
