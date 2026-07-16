"""
routers/web.py — Server-rendered marketing pages and emailed-link landing pages.

Routes:
  GET  /          → Homepage (hero + download CTAs)
  GET  /login     → 302 → /app/ (auth lives in the Flutter app only)
  GET  /register  → 302 → /app/ (auth lives in the Flutter app only)
  GET  /privacy   → Privacy Policy
  GET  /terms     → Terms of Service
  GET  /reset-password       → Password-reset form (link from email)
  POST /web/reset-password
  GET  /verify-email         → Email-verification landing (link from email)

/app/ is served by the StaticFiles mount in main.py (Flutter web build).
All sign-in/sign-up happens inside the Flutter app — the server renders no
auth forms and sets no session cookie.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.constants.privacy import PRIVACY_CONTENT, PRIVACY_DATE
from app.constants.tos import TOS_DATE, TOS_SUMMARY, TOS_VERSION
from app.database import get_db
from app.i18n import resolve_lang
from app.services import auth_service
from app.templating import templates

router = APIRouter(tags=["web"])


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _t(request: Request):
    """Translator bound to the request's resolved language (for page titles)."""
    from app.i18n import translator

    return translator(resolve_lang(request))


# ---------------------------------------------------------------------------
# Public GET pages
# ---------------------------------------------------------------------------

@router.get("/", response_class=HTMLResponse)
def homepage(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    t = _t(request)
    return templates.TemplateResponse(request, "home.html", {
        "page_title": t("home_title"),
        "page_description": t("home_description"),
        "android_download_url": settings.ANDROID_DOWNLOAD_URL,
    })


# Auth lives in the Flutter app — keep redirects so stale bookmarks/old links
# land on the app, which shows its own login when unauthenticated.
@router.get("/login")
def login_page() -> RedirectResponse:
    return RedirectResponse("/app/", status_code=302)


@router.get("/register")
def register_page() -> RedirectResponse:
    return RedirectResponse("/app/", status_code=302)


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
