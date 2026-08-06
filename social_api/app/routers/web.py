"""
routers/web.py — Server-rendered marketing pages and emailed-link landing pages.

Routes:
  GET  /          → Homepage (hero + download CTAs)
  GET  /login     → 302 → /app/ (auth lives in the Flutter app only)
  GET  /register  → 302 → /app/ (auth lives in the Flutter app only)
  GET  /privacy   → Privacy Policy
  GET  /terms     → Terms of Service
  GET  /guidelines → Community Guidelines
  GET  /reset-password       → Password-reset form (link from email)
  POST /web/reset-password
  GET  /verify-email         → Email-verification landing (link from email)
  GET  /robots.txt           → keeps /admin out of search indexes
  GET  /appeal/{token}       → Moderation appeal form (link from email)
  POST /web/appeal
  GET  /appeal               → Request an appeal link by email (suspended users)
  POST /web/appeal-request

/app/ is served by the StaticFiles mount in main.py (Flutter web build).
All sign-in/sign-up happens inside the Flutter app — the server renders no
auth forms and sets no session cookie. The appeal pages are the one exception:
a suspended user cannot authenticate at all, so their appeal path must be a
server-rendered form authorized by a signed link instead of a session.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.constants.guidelines import (
    GUIDELINES_CONTENT,
    GUIDELINES_DATE,
    GUIDELINES_VERSION,
)
from app.constants.privacy import PRIVACY_CONTENT, PRIVACY_DATE
from app.constants.tos import TOS_DATE, TOS_SUMMARY, TOS_VERSION
from app.database import get_db
from app.i18n import resolve_lang
from app.limiter import limiter
from app.models.moderation_log import ModerationLog
from app.models.user import User
from app.services import appeal_service, appeal_token, auth_service, email_service
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


@router.get("/guidelines", response_class=HTMLResponse)
def guidelines_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "guidelines.html", {
        "page_title": "Community Guidelines — Ntripi",
        "content": GUIDELINES_CONTENT,
        "last_updated": GUIDELINES_DATE,
        "guidelines_version": GUIDELINES_VERSION,
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


# ---------------------------------------------------------------------------
# robots.txt
# ---------------------------------------------------------------------------

@router.get("/robots.txt", response_class=PlainTextResponse)
def robots_txt() -> PlainTextResponse:
    # Only /admin is disallowed — /app deep links are user-shareable and fine to
    # index. The admin pages additionally carry X-Robots-Tag: noindex.
    return PlainTextResponse("User-agent: *\nDisallow: /admin/\n")


# ---------------------------------------------------------------------------
# Moderation appeals (public — a suspended user cannot authenticate)
# ---------------------------------------------------------------------------

def _appeal_invalid(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "token_invalid.html", {
        "page_title": "Link expired — Ntripi",
        "message": "This appeal link is invalid or has expired.",
    }, status_code=200)


@router.get("/appeal/{token}", response_class=HTMLResponse)
def appeal_form(request: Request, token: str, db: Session = Depends(get_db)) -> HTMLResponse:
    claims = appeal_token.decode_appeal_token(token)
    if claims is None:
        return _appeal_invalid(request)

    return templates.TemplateResponse(request, "appeal_form.html", {
        "page_title": "Appeal a decision — Ntripi",
        "token": token,
        "action_label": _ACTION_LABELS.get(claims.get("target_type"), "decision"),
    })


# Human-readable subject of the appeal, derived from what the link points at.
_ACTION_LABELS = {"itinerary": "removed itinerary", "user": "account decision"}


@router.post("/web/appeal", response_class=HTMLResponse)
@limiter.limit("10/hour")
def web_appeal_submit(
    request: Request,  # required first positional for slowapi rate limiting
    token: str = Form(...),
    reason: str = Form(""),
    db: Session = Depends(get_db),
) -> HTMLResponse:
    claims = appeal_token.decode_appeal_token(token)
    if claims is None:
        return _appeal_invalid(request)

    try:
        user_id = uuid.UUID(claims["sub"])
        target_id = uuid.UUID(claims["target_id"]) if claims.get("target_id") else None
    except (ValueError, TypeError, KeyError):
        return _appeal_invalid(request)

    user = db.get(User, user_id)
    if user is None or target_id is None:
        return _appeal_invalid(request)

    def _form_error(msg: str) -> HTMLResponse:
        return templates.TemplateResponse(request, "appeal_form.html", {
            "page_title": "Appeal a decision — Ntripi",
            "token": token,
            "action_label": _ACTION_LABELS.get(claims.get("target_type"), "decision"),
            "error_message": msg,
        }, status_code=200)

    try:
        appeal_service.create_appeal(
            db, user, claims.get("target_type", ""), target_id, reason,
            log_id=uuid.UUID(claims["log_id"]) if claims.get("log_id") else None,
        )
    except appeal_service.AppealError as exc:
        return _form_error(exc.message)

    return templates.TemplateResponse(request, "appeal_done.html", {
        "page_title": "Appeal received — Ntripi",
    })


@router.get("/appeal", response_class=HTMLResponse)
def appeal_request_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "appeal_request.html", {
        "page_title": "Appeal a decision — Ntripi",
    })


@router.post("/web/appeal-request", response_class=HTMLResponse)
@limiter.limit("5/hour")
def web_appeal_request(
    request: Request,  # required first positional for slowapi rate limiting
    email: str = Form(""),
    db: Session = Depends(get_db),
) -> HTMLResponse:
    """Email a fresh appeal link. Always renders the same confirmation, whether
    or not the address exists — enumeration-safe, like the password-reset flow."""
    address = (email or "").strip().lower()
    if address:
        user = db.execute(select(User).where(User.email == address)).scalar_one_or_none()
        if user is not None:
            action = db.execute(
                select(ModerationLog)
                .where(
                    ModerationLog.target_type == "user",
                    ModerationLog.target_id == user.id,
                    ModerationLog.action.in_(appeal_service.APPEALABLE_ACTIONS),
                )
                .order_by(ModerationLog.created_at.desc())
            ).scalars().first()
            if action is not None:
                from app.services.auth_service import _email_html

                link = appeal_token.appeal_link(
                    appeal_token.mint_appeal_token(user.id, "user", user.id, action.id)
                )
                email_service.send_email(
                    to=user.email,
                    subject="Ntripi — Appeal a moderation decision",
                    html=_email_html(
                        "Appeal a moderation decision",
                        "Use the link below to explain why you believe the decision "
                        "against your account was incorrect. A moderator will review it.",
                        "Appeal this decision",
                        link,
                    ),
                )

    return templates.TemplateResponse(request, "appeal_done.html", {
        "page_title": "Check your email — Ntripi",
        "check_email": True,
    })
