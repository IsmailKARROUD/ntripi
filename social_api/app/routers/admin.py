"""
routers/admin.py — Internal moderation dashboard (server-rendered Jinja2).

Two independent auth layers guard every route:

  1. HTTP Basic (ADMIN_BASIC_USERNAME/PASSWORD). If either env var is unset the
     whole dashboard 404s — the panel is invisible, not merely locked.
  2. A per-admin session cookie minted by POST /admin/login, holding a JWT with
     scope="admin". The scope claim is mandatory on decode: an API access token
     is signed with the same key, so without that check a stolen 15-minute
     mobile token would open the dashboard.

CSRF defense is the cookie's SameSite=Strict plus the fact that every mutation
is a POST — a cross-site form post simply arrives without the cookie. All
mutations follow Post/Redirect/Get so a refresh can't replay an action.

Pages are English-only (single-operator tool) and excluded from the OpenAPI
schema. `Cache-Control: no-store` + `X-Robots-Tag: noindex` are applied to every
/admin response by SecurityHeadersMiddleware.
"""

from __future__ import annotations

import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.limiter import limiter
from app.models.appeal import Appeal
from app.models.content_report import ContentReport
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.legal_escalation import LegalEscalation
from app.models.moderation_log import HIDE_FAMILY
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import (
    admin_service, appeal_service, auth_service, moderation_actions,
)
from app.services.share_service import build_share_url
from app.templating import templates

ADMIN_COOKIE = "ntripi_admin_session"
_ADMIN_SCOPE = "admin"
_LOG_PAGE_SIZE = 50

_basic_scheme = HTTPBasic(auto_error=False)


# ---------------------------------------------------------------------------
# Layer 1 — HTTP Basic
# ---------------------------------------------------------------------------

def _require_basic(
    credentials: HTTPBasicCredentials | None = Depends(_basic_scheme),
    settings: Settings = Depends(get_settings),
) -> None:
    expected_user = settings.ADMIN_BASIC_USERNAME
    expected_pass = settings.ADMIN_BASIC_PASSWORD

    # Feature off unless BOTH are configured — 404 so the panel's existence
    # isn't advertised by a 401 challenge.
    if not expected_user or not expected_pass:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not Found")

    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Not authenticated",
        headers={"WWW-Authenticate": "Basic"},
    )
    if credentials is None:
        raise unauthorized

    # Compare both fields unconditionally — timing-safe, same rule as login.
    user_ok = secrets.compare_digest(
        credentials.username.encode("utf-8"), expected_user.encode("utf-8")
    )
    pass_ok = secrets.compare_digest(
        credentials.password.encode("utf-8"), expected_pass.encode("utf-8")
    )
    if not (user_ok and pass_ok):
        raise unauthorized


router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    include_in_schema=False,
    dependencies=[Depends(_require_basic)],
)


# ---------------------------------------------------------------------------
# Layer 2 — admin session cookie
# ---------------------------------------------------------------------------

def _mint_admin_session(user: User, settings: Settings) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": str(user.id),
            "scope": _ADMIN_SCOPE,
            "iat": now,
            "exp": now + timedelta(minutes=settings.ADMIN_SESSION_EXPIRE_MINUTES),
        },
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )


def _login_redirect() -> HTTPException:
    # 303 from a dependency: FastAPI's handler preserves the Location header and
    # browsers follow it, so an expired session lands on the login form.
    return HTTPException(
        status_code=status.HTTP_303_SEE_OTHER,
        detail="admin login required",
        headers={"Location": "/admin/login"},
    )


def _require_admin_page(
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> User:
    token = request.cookies.get(ADMIN_COOKIE)
    if not token:
        raise _login_redirect()

    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
    except JWTError:
        raise _login_redirect()

    # Mandatory: an API access token (no scope) must never unlock the dashboard.
    if payload.get("scope") != _ADMIN_SCOPE:
        raise _login_redirect()

    try:
        user_id = uuid.UUID(payload.get("sub") or "")
    except ValueError:
        raise _login_redirect()

    user = db.get(User, user_id)
    if user is None or not user.is_admin or not user.is_active:
        raise _login_redirect()
    return user


def _page(request: Request, name: str, context: dict, status_code: int = 200) -> HTMLResponse:
    return templates.TemplateResponse(
        request, f"admin/{name}", context, status_code=status_code
    )


def _redirect(path: str, error: str | None = None, notice: str | None = None):
    # Split any #fragment off first: the query has to sit before it, or the whole
    # "?notice=..." would be parsed as part of the fragment and never rendered.
    path, _, fragment = path.partition("#")
    query = ""
    if error:
        query = f"?error={error}"
    elif notice:
        query = f"?notice={notice}"
    suffix = f"#{fragment}" if fragment else ""
    return RedirectResponse(
        f"{path}{query}{suffix}", status_code=status.HTTP_303_SEE_OTHER,
    )


# ---------------------------------------------------------------------------
# Login / logout
# ---------------------------------------------------------------------------

@router.get("/login", response_class=HTMLResponse)
def admin_login_form(request: Request) -> HTMLResponse:
    return _page(request, "login.html", {"page_title": "Admin sign in"})


@router.post("/login")
@limiter.limit("10/minute")
def admin_login(
    request: Request,  # required first positional for slowapi rate limiting
    identifier: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
):
    invalid = _page(
        request, "login.html",
        {"page_title": "Admin sign in", "error_message": "Invalid credentials."},
        status_code=401,
    )
    try:
        # Reuses the app's timing-safe password check (and its deactivated-account
        # guard); admin rights are then checked separately.
        user, _token = auth_service.authenticate_user(identifier, password, db)
    except auth_service.AuthError:
        return invalid

    if not user.is_admin:
        return invalid

    response = RedirectResponse("/admin", status_code=status.HTTP_303_SEE_OTHER)
    response.set_cookie(
        ADMIN_COOKIE,
        _mint_admin_session(user, settings),
        max_age=settings.ADMIN_SESSION_EXPIRE_MINUTES * 60,
        httponly=True,
        # Not over plain http in dev, or the cookie is silently dropped.
        secure=not settings.DEBUG,
        # Strict is the CSRF defense for every POST in this router.
        samesite="strict",
        path="/admin",
    )
    return response


@router.post("/logout")
def admin_logout():
    response = RedirectResponse("/admin/login", status_code=status.HTTP_303_SEE_OTHER)
    response.delete_cookie(ADMIN_COOKIE, path="/admin")
    return response


# ---------------------------------------------------------------------------
# Overview
# ---------------------------------------------------------------------------

@router.get("", response_class=HTMLResponse)
def admin_dashboard(
    request: Request,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    return _page(request, "dashboard.html", {
        "page_title": "Overview",
        "admin": admin,
        "counts": admin_service.overview_counts(db),
        "recent": admin_service.recent_log(db, limit=20),
    })


# ---------------------------------------------------------------------------
# Reports queue
# ---------------------------------------------------------------------------

@router.get("/reports", response_class=HTMLResponse)
def admin_reports(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    reports = admin_service.pending_reports(db)
    rows = []
    for report in reports:
        # Reports are polymorphic; only itinerary targets have a cover and a
        # detail page, so the other kinds render as a plain label.
        target = moderation_actions.load_target(db, report.target_type, report.target_id)
        itinerary = target if report.target_type == "itinerary" else None
        rows.append({
            "report": report,
            "itinerary": itinerary,
            "target": target,
            "label": moderation_actions.target_label(report.target_type, target),
            "owner": moderation_actions.target_author(db, report.target_type, target),
            "age": admin_service.humanize_age(report.created_at),
            "sla": admin_service.sla_class(report.created_at),
        })
    return _page(request, "reports.html", {
        "page_title": "Reports",
        "admin": admin,
        "rows": rows,
        "error_message": error,
        "notice_message": notice,
    })


@router.post("/reports/{report_id}/action")
def admin_report_action(
    report_id: uuid.UUID,
    action: str = Form(...),
    reason: str = Form(""),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    report = db.get(ContentReport, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found")

    reason = (reason or "").strip()
    if not reason:
        return _redirect("/admin/reports", error="A reason is required.")
    if report.resolution != "pending":
        # Another tab (or a double submit) already handled it.
        return _redirect("/admin/reports", notice="That report was already resolved.")

    # A CSAM escalation must not be closable from the routine queue — that is
    # the entire reason the separate lane exists.
    if action == "dismiss" and admin_service.has_open_escalation(db, report):
        return _redirect(
            "/admin/reports",
            error="This report is legally escalated — close it from the Legal page.",
        )

    target = moderation_actions.load_target(db, report.target_type, report.target_id)
    itinerary = target if report.target_type == "itinerary" else None
    owner = moderation_actions.target_author(db, report.target_type, target)

    if action == "dismiss":
        admin_service.dismiss_report(db, admin, report, reason)
    elif action in ("hide", "delete"):
        if target is None:
            return _redirect("/admin/reports", error="The reported content no longer exists.")
        if itinerary is None:
            # Ratings and profiles have no soft-delete state — hide is the only
            # content penalty available for them.
            admin_service.hide_reported_target(db, admin, report, target, reason)
        elif action == "hide":
            admin_service.hide_itinerary(db, admin, itinerary, reason, report)
        else:
            admin_service.soft_delete_itinerary(db, admin, itinerary, reason, report)
    elif action in ("warn", "ban"):
        if owner is None:
            return _redirect("/admin/reports", error="The content author no longer exists.")
        if action == "warn":
            admin_service.warn_user(db, admin, owner, reason, report)
        else:
            admin_service.ban_user(db, admin, owner, reason, report)
    else:
        return _redirect("/admin/reports", error="Unknown action.")

    return _redirect("/admin/reports", notice="Action applied.")


@router.post("/reports/bulk")
def admin_reports_bulk(
    action: str = Form(...),
    reason: str = Form(""),
    report_ids: list[uuid.UUID] = Form(default=[]),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    reason = (reason or "").strip()
    if not reason:
        return _redirect("/admin/reports", error="A reason is required.")
    if not report_ids:
        return _redirect("/admin/reports", error="Select at least one report.")
    if action not in ("dismiss", "delete"):
        return _redirect("/admin/reports", error="Unknown bulk action.")

    handled = admin_service.bulk_resolve(db, admin, list(report_ids), action, reason)
    return _redirect("/admin/reports", notice=f"{handled} report(s) processed.")


# ---------------------------------------------------------------------------
# Flagged uploads queue
# ---------------------------------------------------------------------------

@router.get("/flagged", response_class=HTMLResponse)
def admin_flagged(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    rows = []
    for log_row in admin_service.flagged_queue(db):
        itinerary = (
            db.get(Itinerary, log_row.target_itinerary_id)
            if log_row.target_itinerary_id else None
        )
        rows.append({
            "log": log_row,
            "itinerary": itinerary,
            "uploader": (
                db.get(User, log_row.uploader_user_id)
                if log_row.uploader_user_id else None
            ),
            "age": admin_service.humanize_age(log_row.created_at),
            "sla": admin_service.sla_class(log_row.created_at),
        })
    return _page(request, "flagged.html", {
        "page_title": "Flagged uploads",
        "admin": admin,
        "rows": rows,
        "error_message": error,
        "notice_message": notice,
    })


@router.post("/flagged/{log_id}/action")
async def admin_flagged_action(
    log_id: uuid.UUID,
    action: str = Form(...),
    reason: str = Form(""),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    log_row = db.get(ImageModerationLog, log_id)
    if log_row is None:
        raise HTTPException(status_code=404, detail="Flagged upload not found")

    reason = (reason or "").strip()
    if not reason:
        return _redirect("/admin/flagged", error="A reason is required.")
    if log_row.reviewed_at is not None:
        return _redirect("/admin/flagged", notice="That upload was already reviewed.")

    if action == "approve":
        admin_service.approve_flagged(db, admin, log_row, reason)
    elif action == "remove":
        await admin_service.remove_flagged_image(db, admin, log_row, reason)
    elif action in ("warn", "ban"):
        uploader = (
            db.get(User, log_row.uploader_user_id)
            if log_row.uploader_user_id else None
        )
        if uploader is None:
            return _redirect("/admin/flagged", error="The uploader no longer exists.")
        # Clear the row from the queue too — the operator has judged it.
        log_row.reviewed_at = datetime.now(timezone.utc)
        if action == "warn":
            admin_service.warn_user(db, admin, uploader, reason)
        else:
            admin_service.ban_user(db, admin, uploader, reason)
    else:
        return _redirect("/admin/flagged", error="Unknown action.")

    return _redirect("/admin/flagged", notice="Action applied.")


# ---------------------------------------------------------------------------
# Text-flag queue (classifier said "review", nobody has looked yet)
# ---------------------------------------------------------------------------

def _decision_target(db: Session, decision) -> dict:
    """Resolve a polymorphic decision target into something renderable."""
    target = moderation_actions.load_target(db, decision.target_type, decision.target_id)
    author = moderation_actions.target_author(db, decision.target_type, target)
    return {
        "decision": decision,
        "target": target,
        "author": author,
        "label": moderation_actions.target_label(decision.target_type, target),
        # Highest-scoring categories first — what the moderator needs to see.
        "scores": sorted(
            (decision.scores or {}).items(), key=lambda item: item[1], reverse=True
        )[:5],
        "age": admin_service.humanize_age(decision.created_at),
        "sla": admin_service.sla_class(decision.created_at),
    }


@router.get("/text-flags", response_class=HTMLResponse)
def admin_text_flags(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    rows = [
        _decision_target(db, decision)
        for decision in admin_service.pending_text_flags(db)
    ]
    return _page(request, "text_flags.html", {
        "page_title": "Text flags",
        "admin": admin,
        "rows": rows,
        "error_message": error,
        "notice_message": notice,
    })


@router.post("/text-flags/{decision_id}/action")
def admin_text_flag_action(
    decision_id: uuid.UUID,
    action: str = Form(...),
    reason: str = Form(""),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    decision = db.get(TextModerationDecision, decision_id)
    if decision is None:
        raise HTTPException(status_code=404, detail="Decision not found")

    reason = (reason or "").strip()
    if not reason:
        return _redirect("/admin/text-flags", error="A reason is required.")
    if decision.reviewed_at is not None:
        return _redirect("/admin/text-flags", notice="That flag was already reviewed.")
    if action not in ("approve", "hide"):
        return _redirect("/admin/text-flags", error="Unknown action.")

    admin_service.resolve_text_flag(db, admin, decision, action, reason)
    return _redirect("/admin/text-flags", notice="Action applied.")


# ---------------------------------------------------------------------------
# Legal escalations (CSAM) — cannot be closed as a routine moderation item
# ---------------------------------------------------------------------------

@router.get("/legal", response_class=HTMLResponse)
def admin_legal(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    rows = []
    for escalation in admin_service.open_legal_escalations(db):
        target = moderation_actions.load_target(
            db, escalation.target_type, escalation.target_id
        )
        rows.append({
            "escalation": escalation,
            "target": target,
            "author": moderation_actions.target_author(db, escalation.target_type, target),
            "label": moderation_actions.target_label(escalation.target_type, target),
            "age": admin_service.humanize_age(escalation.created_at),
        })
    return _page(request, "legal.html", {
        "page_title": "Legal escalations",
        "admin": admin,
        "rows": rows,
        "error_message": error,
        "notice_message": notice,
    })


@router.post("/legal/takedown")
async def admin_legal_takedown(
    path: str = Form(""),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    """Action a path from a Cloudflare CSAM Scanning Tool notice."""
    try:
        result = await admin_service.csam_takedown(db, admin, path)
    except ValueError as exc:
        return _redirect("/admin/legal", error=str(exc))

    notice = (
        f"Removed {result['key']} and suspended @{result['username']}. "
        f"Evidence hash: {result['image_hash']}. "
        "File the CyberTipline report within 24h, then close the escalation "
        "below with the report number."
    )
    if not result["object_found"]:
        notice += " (Object was already gone — hash unavailable.)"
    return _redirect("/admin/legal", notice=notice)


@router.post("/legal/{escalation_id}/close")
def admin_legal_close(
    escalation_id: uuid.UUID,
    note: str = Form(""),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    escalation = db.get(LegalEscalation, escalation_id)
    if escalation is None:
        raise HTTPException(status_code=404, detail="Escalation not found")

    try:
        admin_service.close_escalation(db, admin, escalation, note)
    except ValueError:
        # The note is the whole point — this category must never be closed with
        # a single click and no record of the judgement.
        return _redirect(
            "/admin/legal",
            error="A written note is required to close a legal escalation.",
        )
    return _redirect("/admin/legal", notice="Escalation closed.")


# ---------------------------------------------------------------------------
# Appeals queue
# ---------------------------------------------------------------------------

@router.get("/appeals", response_class=HTMLResponse)
def admin_appeals(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    rows = []
    for appeal in admin_service.pending_appeals(db):
        target = moderation_actions.load_target(db, appeal.target_type, appeal.target_id)
        itinerary = target if appeal.target_type == admin_service.TARGET_ITINERARY else None
        owner = db.get(User, appeal.user_id)
        rows.append({
            "appeal": appeal,
            "user": owner,
            "itinerary": itinerary,
            # Rating and profile appeals used to render with no target at all;
            # the label is what the template shows when there is no itinerary.
            "target_label": moderation_actions.target_label(appeal.target_type, target),
            "target_missing": target is None,
            # Restoring content owned by a still-banned user won't make it public
            # again — surface that so the operator can unban too.
            "owner_banned": owner is not None and not owner.is_active,
            "age": admin_service.humanize_age(appeal.created_at),
            "sla": admin_service.sla_class(appeal.created_at),
        })
    return _page(request, "appeals.html", {
        "page_title": "Appeals",
        "admin": admin,
        "rows": rows,
        "error_message": error,
        "notice_message": notice,
    })


@router.post("/appeals/{appeal_id}/decide")
def admin_appeal_decide(
    appeal_id: uuid.UUID,
    decision: str = Form(...),
    admin_response: str = Form(""),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    appeal = db.get(Appeal, appeal_id)
    if appeal is None:
        raise HTTPException(status_code=404, detail="Appeal not found")
    if decision not in appeal_service.DECISIONS:
        return _redirect("/admin/appeals", error="Unknown decision.")

    try:
        appeal_service.decide_appeal(db, admin, appeal, decision, admin_response)
    except appeal_service.AppealError as exc:
        return _redirect("/admin/appeals", notice=exc.message)

    return _redirect("/admin/appeals", notice="Appeal decided.")


# ---------------------------------------------------------------------------
# Audit log + reversals
# ---------------------------------------------------------------------------

@router.get("/log", response_class=HTMLResponse)
def admin_log(
    request: Request,
    page: int = 1,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    page = max(1, page)
    offset = (page - 1) * _LOG_PAGE_SIZE
    rows = admin_service.recent_log(db, limit=_LOG_PAGE_SIZE + 1, offset=offset)
    has_next = len(rows) > _LOG_PAGE_SIZE
    return _page(request, "log.html", {
        "page_title": "Moderation log",
        "admin": admin,
        "rows": rows[:_LOG_PAGE_SIZE],
        # Which actions the template may offer to reverse — shared with
        # appeal_service so the two cannot disagree about what is undoable.
        "hide_family": HIDE_FAMILY,
        "page": page,
        "has_next": has_next,
        "error_message": error,
        "notice_message": notice,
    })


# The lanes an action form may bounce back to. An allowlist rather than an
# open `next` — the value arrives in a form post and would otherwise be an open
# redirect off an authenticated admin session.
_LANES = (
    "/admin/hidden", "/admin/hidden#reviews", "/admin/hidden#profiles",
    "/admin/removed", "/admin/suspended", "/admin/log",
)


def _lane(next_path: str | None) -> str:
    return next_path if next_path in _LANES else "/admin/log"


def _itinerary_lane_rows(db: Session, itineraries) -> list[dict]:
    """Shared row shape for the hidden and removed lanes."""
    rows = []
    for itinerary in itineraries:
        owner = db.get(User, itinerary.user_id)
        taken_down = itinerary.deleted_at or itinerary.hidden_at
        rows.append({
            "itinerary": itinerary,
            "owner": owner,
            # Restoring content owned by a still-banned user won't make it
            # public again — surface that so the operator can unban too.
            "owner_banned": owner is not None and not owner.is_active,
            "last_action": admin_service.last_takedown_log(db, itinerary.id),
            "age": admin_service.humanize_age(taken_down),
            "sla": admin_service.sla_class(taken_down),
        })
    return rows


def _status_lane_rows(db: Session, target_type: str, targets) -> list[dict]:
    """Row shape for the rating and profile sections of the hidden lane.

    These carry no hidden_at, so the takedown log row is the only source of
    "when" — age and SLA colour both read off it rather than off the target.
    """
    rows = []
    for target in targets:
        owner = moderation_actions.target_author(db, target_type, target)
        last_action = admin_service.last_takedown_log(db, target.id, target_type)
        taken_down = last_action.created_at if last_action else None
        rows.append({
            "target": target,
            "target_type": target_type,
            "owner": owner,
            # Restoring content owned by a still-banned user won't make it
            # public again — surface that so the operator can unban too.
            "owner_banned": owner is not None and not owner.is_active,
            "last_action": last_action,
            "age": admin_service.humanize_age(taken_down),
            "sla": admin_service.sla_class(taken_down),
        })
    return rows


@router.get("/hidden", response_class=HTMLResponse)
def admin_hidden(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    """Content that is down but not removed.

    Its own lane because an auto-hide leaves no queue entry anywhere else: the
    triggering report is resolved as 'auto_hidden' the moment the threshold is
    crossed, so /admin/reports never shows it and only /admin/log records it.
    """
    return _page(request, "hidden.html", {
        "page_title": "Hidden content",
        "admin": admin,
        "rows": _itinerary_lane_rows(db, admin_service.hidden_itineraries(db)),
        # Reviews and profiles share the lane rather than adding two nav entries:
        # "down but not removed" is the same operator question for all three, and
        # an auto-hide leaves no queue entry anywhere else for any of them.
        "rating_rows": _status_lane_rows(
            db, moderation_actions.TARGET_RATING, admin_service.hidden_ratings(db),
        ),
        "profile_rows": _status_lane_rows(
            db, moderation_actions.TARGET_USER, admin_service.hidden_profiles(db),
        ),
        "error_message": error,
        "notice_message": notice,
    })


@router.get("/removed", response_class=HTMLResponse)
def admin_removed(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    return _page(request, "removed.html", {
        "page_title": "Removed itineraries",
        "admin": admin,
        "rows": _itinerary_lane_rows(db, admin_service.removed_itineraries(db)),
        "error_message": error,
        "notice_message": notice,
    })


@router.get("/suspended", response_class=HTMLResponse)
def admin_suspended(
    request: Request,
    error: str | None = None,
    notice: str | None = None,
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    rows = [
        {"user": user, "age": admin_service.humanize_age(user.updated_at)}
        for user in admin_service.suspended_users(db)
    ]
    return _page(request, "suspended.html", {
        "page_title": "Suspended accounts",
        "admin": admin,
        "rows": rows,
        "error_message": error,
        "notice_message": notice,
    })


@router.get("/itineraries/{itinerary_id}", response_class=HTMLResponse)
def admin_itinerary_detail(
    itinerary_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
    admin: User = Depends(_require_admin_page),
) -> HTMLResponse:
    """Read-only inspection page — reachable from every queue and log row."""
    detail = admin_service.itinerary_detail(db, itinerary_id)
    if detail is None:
        # Log rows keep target_id after a hard delete, so this link is reachable
        # for purged content — render the shell, not a raw error.
        return _page(
            request, "itinerary.html",
            {"page_title": "Itinerary", "admin": admin, "itinerary": None},
            status_code=404,
        )

    return _page(request, "itinerary.html", {
        "page_title": detail["itinerary"].title,
        "admin": admin,
        **detail,
        "share_url": build_share_url(detail["itinerary"], settings),
    })


@router.post("/itineraries/{itinerary_id}/unhide")
def admin_unhide(
    itinerary_id: uuid.UUID,
    reason: str = Form(""),
    next: str = Form("/admin/log"),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    back = _lane(next)
    reason = (reason or "").strip()
    if not reason:
        return _redirect(back, error="A reason is required.")
    itinerary = db.get(Itinerary, itinerary_id)
    if itinerary is None:
        return _redirect(back, error="That itinerary no longer exists.")

    admin_service.unhide_itinerary(db, admin, itinerary, reason)
    return _redirect(back, notice="Itinerary is visible again.")


@router.post("/itineraries/{itinerary_id}/restore")
def admin_restore(
    itinerary_id: uuid.UUID,
    reason: str = Form(""),
    next: str = Form("/admin/removed"),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    """Reverse a soft delete. Separate from unhide so the audit row names the
    column that changed, even though both clear all takedown state."""
    back = _lane(next)
    reason = (reason or "").strip()
    if not reason:
        return _redirect(back, error="A reason is required.")
    itinerary = db.get(Itinerary, itinerary_id)
    if itinerary is None:
        return _redirect(back, error="That itinerary no longer exists.")

    admin_service.restore_itinerary(db, admin, itinerary, reason)
    return _redirect(back, notice="Itinerary restored.")


@router.post("/itineraries/{itinerary_id}/remove")
def admin_remove(
    itinerary_id: uuid.UUID,
    reason: str = Form(""),
    next: str = Form("/admin/hidden"),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    """Remove without a pending report. The reports lane can only reach
    soft_delete_itinerary through a report, which an auto-hide has already
    resolved — so this is the only removal path for auto-hidden content."""
    back = _lane(next)
    reason = (reason or "").strip()
    if not reason:
        return _redirect(back, error="A reason is required.")
    itinerary = db.get(Itinerary, itinerary_id)
    if itinerary is None:
        return _redirect(back, error="That itinerary no longer exists.")
    if itinerary.deleted_at is not None:
        return _redirect(back, error="That itinerary is already removed.")

    admin_service.soft_delete_itinerary(db, admin, itinerary, reason)
    return _redirect(back, notice="Itinerary removed.")


@router.post("/ratings/{rating_id}/unhide")
def admin_unhide_rating(
    rating_id: uuid.UUID,
    reason: str = Form(""),
    next: str = Form("/admin/hidden"),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    """Reverse a review takedown. Also puts the score back into the itinerary's
    average — see moderation_actions.restore_target."""
    back = _lane(next)
    reason = (reason or "").strip()
    if not reason:
        return _redirect(back, error="A reason is required.")
    rating = db.get(ItineraryRating, rating_id)
    if rating is None:
        return _redirect(back, error="That review no longer exists.")

    admin_service.unhide_target(db, admin, moderation_actions.TARGET_RATING, rating, reason)
    return _redirect(back, notice="Review is visible again.")


@router.post("/users/{user_id}/unhide")
def admin_unhide_profile(
    user_id: uuid.UUID,
    reason: str = Form(""),
    next: str = Form("/admin/hidden"),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    """Restore a hidden display_name + bio. Distinct from unban: a hidden profile
    is a live account, so the two states must stay separately reversible."""
    back = _lane(next)
    reason = (reason or "").strip()
    if not reason:
        return _redirect(back, error="A reason is required.")
    user = db.get(User, user_id)
    if user is None:
        return _redirect(back, error="That user no longer exists.")

    admin_service.unhide_target(db, admin, moderation_actions.TARGET_USER, user, reason)
    return _redirect(back, notice="Profile is visible again.")


@router.post("/users/{user_id}/unban")
def admin_unban(
    user_id: uuid.UUID,
    reason: str = Form(""),
    next: str = Form("/admin/log"),
    db: Session = Depends(get_db),
    admin: User = Depends(_require_admin_page),
):
    back = _lane(next)
    reason = (reason or "").strip()
    if not reason:
        return _redirect(back, error="A reason is required.")
    user = db.get(User, user_id)
    if user is None:
        return _redirect(back, error="That user no longer exists.")

    admin_service.unban_user(db, admin, user, reason)
    return _redirect(back, notice="Account reinstated.")
