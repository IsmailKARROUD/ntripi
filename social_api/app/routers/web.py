"""
routers/web.py — Server-rendered marketing pages and web auth flow.

Routes:
  GET  /          → Homepage (hero + download CTAs)
  GET  /login     → Login form (redirects if already logged in)
  GET  /register  → Register form (redirects if already logged in)
  GET  /privacy   → Privacy Policy
  GET  /terms     → Terms of Service
  GET  /app/      → App shell placeholder (Ticket 8)
  POST /web/login     → Validates credentials, sets cookie, redirects to /app/
  POST /web/register  → Creates account, sets cookie, redirects to /app/

Cookie strategy:
  - Name: ntripi_session
  - HTTP-only, Secure (production only), SameSite=Lax
  - Max-Age matches the JWT expiry configured in settings
"""

from __future__ import annotations

import re
from datetime import datetime
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
from app.services.auth import decode_access_token

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


def _set_session_cookie(
    response: RedirectResponse | HTMLResponse,
    token: str,
    settings: Settings,
) -> None:
    response.set_cookie(
        key="ntripi_session",
        value=token,
        max_age=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
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


@router.get("/app/", response_class=HTMLResponse)
def app_shell(request: Request) -> HTMLResponse:
    # Placeholder until Ticket 8 ships the Flutter web build at this path.
    return HTMLResponse("""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Ntripi</title>
  <style>
    body { font-family: system-ui, sans-serif; text-align: center; padding: 60px 20px; background: #F9FAFB; color: #111827; }
    h1 { color: #4F46E5; font-size: 2rem; margin-bottom: 12px; }
    p { color: #6B7280; margin-bottom: 8px; }
    a { color: #4F46E5; }
  </style>
</head>
<body>
  <h1>Ntripi</h1>
  <p>The web app is coming soon.</p>
  <p><a href="/">Back to homepage</a></p>
</body>
</html>""")


# ---------------------------------------------------------------------------
# Web auth POST handlers
# ---------------------------------------------------------------------------

@router.post("/web/login", response_class=HTMLResponse)
def web_login(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    try:
        user, token = auth_service.authenticate_user(email, password, db)
    except auth_service.AuthError as e:
        return templates.TemplateResponse(
            request,
            "login.html",
            {
                "page_title": "Sign in — Ntripi",
                "error_message": e.message,
                "email": email,
            },
            status_code=200,
        )

    response = RedirectResponse("/app/", status_code=302)
    _set_session_cookie(response, token, settings)
    return response


@router.post("/web/register", response_class=HTMLResponse)
def web_register(
    request: Request,
    email: str = Form(...),
    username: str = Form(...),
    password: str = Form(...),
    password_confirm: str = Form(...),
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
            },
            status_code=200,
        )

    if password != password_confirm:
        return _error("Passwords do not match.")

    if not tos_accepted:
        return _error("You must accept the Terms of Service to register.")

    if not re.match(r"^[a-z0-9_]+$", username):
        return _error(
            "Username may only contain lowercase letters, digits, and underscores."
        )

    if len(password) < 8:
        return _error("Password must be at least 8 characters.")

    if not any(c.isdigit() for c in password):
        return _error("Password must contain at least one digit.")

    try:
        user, token = auth_service.create_user(
            username=username,
            email=email,
            password=password,
            display_name=None,
            tos_accepted=True,
            db=db,
        )
    except auth_service.AuthError as e:
        return _error(e.message)

    response = RedirectResponse("/app/", status_code=302)
    _set_session_cookie(response, token, settings)
    return response
