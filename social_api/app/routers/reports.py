"""
routers/reports.py — content reporting.

POST /reports lets a viewer flag content as inappropriate. Auth is optional:
anonymous reports arrive from the public share landing page, authenticated ones
from the Flutter app. Targets are polymorphic (itinerary / rating / user); stops,
annotations and transport legs are reported as their parent itinerary.

Reports are persisted for review, the operator is emailed (best-effort), and
content that crosses its distinct-reporter threshold is hidden immediately
without waiting for a human (report_service.check_hide_threshold).

Rate limits are DB-backed (per-user 10/day, per-anonymous-IP 3/day — see
report_service). The slowapi decorator adds a coarse per-IP flood backstop whose
limit is env-configurable.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.dependencies import get_current_user_optional
from app.errors import ApiError
from app.limiter import limiter
from app.models.content_report import ContentReport
from app.models.user import User
from app.schemas.report import ReportAck, ReportCreate
from app.services import moderation_actions, report_service
from app.services.moderation_email_service import send_auto_action_email

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Reports"])


def _target_is_reportable(target_type: str, target) -> bool:
    """Whether a reporter could legitimately have seen this target.

    Content that is already gone or hidden 404s identically to a missing one, so
    a probe can never learn that something was moderated.
    """
    if target is None:
        return False
    if target_type == moderation_actions.TARGET_ITINERARY:
        return target.deleted_at is None and target.hidden_at is None
    if target_type == moderation_actions.TARGET_USER:
        return target.is_active
    return True  # ratings: a hidden note is still reportable by whoever saw it


def _target_owner_id(target_type: str, target):
    if target_type == moderation_actions.TARGET_USER:
        return target.id
    return getattr(target, "user_id", None)


@router.post(
    "/reports",
    response_model=ReportAck,
    status_code=status.HTTP_201_CREATED,
    summary="Report content for moderation",
)
# Coarse per-IP flood backstop; business limits are DB-backed below. Callable so
# the limit can be tuned via REPORT_RATE_LIMIT without a redeploy.
@limiter.limit(lambda: get_settings().REPORT_RATE_LIMIT)
def create_report(
    request: Request,
    body: ReportCreate,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_current_user_optional),
    settings: Settings = Depends(get_settings),
) -> ReportAck:
    target_type = body.target_type
    target = moderation_actions.load_target(db, target_type, body.target_id)
    if not _target_is_reportable(target_type, target):
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="itinerary_not_found", detail="Itinerary not found.",
        )

    if current_user is not None and _target_owner_id(target_type, target) == current_user.id:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="report_own_content", detail="You cannot report your own content.",
        )

    reason = report_service.normalize_reason(body.reason)
    cutoff = datetime.now(timezone.utc) - report_service.RATE_WINDOW
    rate_limited = ApiError(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        code="report_rate_limited", detail="Too many reports. Please try again later.",
    )

    if current_user is not None:
        # Re-reporting something you already flagged is idempotent (no new row,
        # no duplicate operator email) — checked before the limit so it never
        # burns quota. This is also what makes the hide thresholds count
        # *distinct* reporters.
        if report_service.has_pending_report(
            db, current_user.id, target_type, body.target_id
        ):
            return ReportAck()
        if report_service.count_recent_user_reports(
            db, current_user.id, cutoff
        ) >= report_service.USER_DAILY_LIMIT:
            raise rate_limited
        report = ContentReport(
            target_type=target_type,
            target_id=body.target_id,
            reporter_user_id=current_user.id,
            reason=reason,
            notes=body.notes,
        )
    else:
        # Real client IP — ProxyHeadersMiddleware already rewrote X-Forwarded-For.
        ip = request.client.host if request.client else "unknown"
        ip_hash = report_service.hash_ip(ip, settings.SECRET_KEY)
        report_service.scrub_expired_ip_hashes(db, cutoff)
        # Re-reporting from the same IP is idempotent (no new row, no duplicate email).
        if report_service.has_pending_report_by_ip(
            db, ip_hash, target_type, body.target_id
        ):
            return ReportAck()
        if report_service.count_recent_ip_reports(
            db, ip_hash, cutoff
        ) >= report_service.IP_DAILY_LIMIT:
            raise rate_limited
        report = ContentReport(
            target_type=target_type,
            target_id=body.target_id,
            reporter_user_id=None,
            reason=reason,
            notes=body.notes,
            reporter_ip_hash=ip_hash,
        )

    db.add(report)
    db.flush()  # the threshold check counts this report too

    # Enough distinct reporters (or one, for the severe categories) takes the
    # content down now rather than waiting for the review deadline.
    outcome = report_service.check_hide_threshold(db, settings, report, target)

    db.commit()
    db.refresh(report)

    if outcome.hidden and outcome.author is not None:
        try:
            send_auto_action_email(
                outcome.author,
                action="auto_hide_reports",
                item_label=outcome.item_label,
                category=outcome.category,
                settings=settings,
                log_id=outcome.log_id,
                target_type=target_type,
                target_id=body.target_id,
            )
        except Exception:
            # A mail outage must never fail the report or undo the hide.
            logger.exception("auto-hide author notification failed")

    try:
        report_service.send_report_notification(
            report, target, current_user, settings, hidden=outcome.hidden,
        )
    except Exception:
        # A mail outage must never fail the report the user just filed.
        logger.exception("report notification email failed")

    return ReportAck()
