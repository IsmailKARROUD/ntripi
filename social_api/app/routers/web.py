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
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.constants.guidelines import (
    GUIDELINES_DATE,
    GUIDELINES_VERSION,
    get_guidelines,
)
from app.constants.privacy import PRIVACY_DATE, PRIVACY_VERSION, get_privacy
from app.constants.tos import TOS_DATE, TOS_VERSION, get_tos
from app.database import get_db
from app.i18n import resolve_lang
from app.limiter import limiter
from app.models.moderation_log import ModerationLog
from app.models.user import User
from app.services import (
    appeal_service, appeal_token, auth_service, email_service, help_service, seo,
)
from app.templating import templates

router = APIRouter(tags=["web"])


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _alt_langs(path: str) -> tuple[str, ...]:
    """The hreflang set for one sitemap entry — the same rule the pages use."""
    from app.i18n import SUPPORTED

    return seo.HELP_CONTENT_LANGS if path.startswith(seo.HELP_PREFIX) else SUPPORTED


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


def _legal_page(
    request: Request,
    *,
    heading_key: str,
    desc_key: str,
    notice_key: str,
    body: str,
    date: str,
    version: str,
) -> HTMLResponse:
    """Render one of the three legal documents in the request's language.

    `notice` is the prevailing-language clause — empty for English, which is
    the authoritative text and so has nothing to prevail over.
    """
    t = _t(request)
    heading = t(heading_key)
    return templates.TemplateResponse(request, "legal.html", {
        "page_title": f"{heading} — Ntripi",
        "page_description": t(desc_key),
        "heading": heading,
        "content": body,
        "last_updated": date,
        "version": version,
        "notice": t(notice_key),
    })


@router.get("/privacy", response_class=HTMLResponse)
def privacy_page(request: Request) -> HTMLResponse:
    return _legal_page(
        request,
        heading_key="legal_privacy_heading",
        desc_key="legal_desc_privacy",
        notice_key="legal_notice_privacy",
        body=get_privacy(resolve_lang(request)),
        date=PRIVACY_DATE,
        version=PRIVACY_VERSION,
    )


@router.get("/terms", response_class=HTMLResponse)
def terms_page(request: Request) -> HTMLResponse:
    return _legal_page(
        request,
        heading_key="legal_terms_heading",
        desc_key="legal_desc_terms",
        notice_key="legal_notice_terms",
        body=get_tos(resolve_lang(request)),
        date=TOS_DATE,
        version=TOS_VERSION,
    )


@router.get("/guidelines", response_class=HTMLResponse)
def guidelines_page(request: Request) -> HTMLResponse:
    return _legal_page(
        request,
        heading_key="legal_guidelines_heading",
        desc_key="legal_desc_guidelines",
        notice_key="legal_notice_guidelines",
        body=get_guidelines(resolve_lang(request)),
        date=GUIDELINES_DATE,
        version=GUIDELINES_VERSION,
    )


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
def robots_txt(settings: Settings = Depends(get_settings)) -> PlainTextResponse:
    # Only /admin is disallowed — /app deep links are user-shareable and fine to
    # index. The admin pages additionally carry X-Robots-Tag: noindex.
    #
    # No named GPTBot / ClaudeBot / CCBot groups, deliberately: a named
    # user-agent group *replaces* the `*` group for that crawler rather than
    # adding to it, so an "Allow: /" block written to welcome an AI crawler
    # would also hand it /admin. The `*` group already allows everything else.
    return PlainTextResponse(
        "User-agent: *\n"
        "Disallow: /admin/\n"
        "\n"
        f"Sitemap: {seo.absolute('/sitemap.xml', settings)}\n"
    )


# ---------------------------------------------------------------------------
# Machine-readable surfaces
#
# Siblings of robots.txt rather than /help routes: they describe the whole site.
# All three read constants/help/en.py, the same tuple the router walks, so the
# sitemap cannot list a page that does not exist or miss one that does.
# ---------------------------------------------------------------------------

@router.get("/sitemap.xml")
def sitemap_xml(request: Request, settings: Settings = Depends(get_settings)) -> Response:
    # media_type is explicit: TemplateResponse defaults to text/html, and a
    # sitemap served as HTML is silently ignored by every crawler.
    return templates.TemplateResponse(
        request, "sitemap.xml",
        {"pages": [
            (seo.absolute(path, settings), changefreq, priority,
             seo.hreflang_alternates(path, settings, langs=_alt_langs(path)))
            for path, changefreq, priority in seo.sitemap_paths()
        ]},
        media_type="application/xml",
    )


@router.get("/llms.txt", response_class=PlainTextResponse)
def llms_txt(settings: Settings = Depends(get_settings)) -> PlainTextResponse:
    return PlainTextResponse(help_service.llms_txt(settings))


@router.get("/llms-full.txt", response_class=PlainTextResponse)
def llms_full_txt(
    lang: str = "en",
    settings: Settings = Depends(get_settings),
) -> PlainTextResponse:
    # `lang` from the query string only, like the other machine surfaces: the
    # URL is the whole cache key, so a CDN cannot serve one reader's language
    # to another.
    resolved = lang if lang in seo.HELP_CONTENT_LANGS else "en"
    return PlainTextResponse(help_service.llms_full_txt(resolved, settings))


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
