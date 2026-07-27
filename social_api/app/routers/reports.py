"""
routers/reports.py — content reporting.

POST /reports lets a viewer flag an itinerary as inappropriate. Auth is optional:
anonymous reports arrive from the public share landing page, authenticated ones
from the Flutter app. Reports are persisted for manual operator review and an
operator notification email is sent (best-effort).

Rate limits are DB-backed (per-user 10/day, per-anonymous-IP 3/day — see
report_service). The slowapi decorator adds a coarse per-IP flood backstop.
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
from app.models.itinerary import Itinerary
from app.models.user import User
from app.schemas.report import ReportAck, ReportCreate
from app.services import report_service

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Reports"])


@router.post(
    "/reports",
    response_model=ReportAck,
    status_code=status.HTTP_201_CREATED,
    summary="Report an itinerary for moderation",
)
@limiter.limit("20/hour")  # coarse per-IP flood backstop; business limits are DB-backed below
def create_report(
    request: Request,
    body: ReportCreate,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_current_user_optional),
    settings: Settings = Depends(get_settings),
) -> ReportAck:
    itinerary = db.get(Itinerary, body.itinerary_id)
    if itinerary is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="itinerary_not_found", detail="Itinerary not found.",
        )

    if current_user is not None and itinerary.user_id == current_user.id:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="report_own_content", detail="You cannot report your own content.",
        )

    cutoff = datetime.now(timezone.utc) - report_service.RATE_WINDOW
    rate_limited = ApiError(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        code="report_rate_limited", detail="Too many reports. Please try again later.",
    )

    if current_user is not None:
        # Re-reporting an itinerary you already flagged is idempotent (no new row,
        # no duplicate operator email) — checked before the limit so it never
        # burns quota.
        if report_service.has_pending_report(db, current_user.id, itinerary.id):
            return ReportAck()
        if report_service.count_recent_user_reports(db, current_user.id, cutoff) >= report_service.USER_DAILY_LIMIT:
            raise rate_limited
        report = ContentReport(
            reported_itinerary_id=itinerary.id,
            reporter_user_id=current_user.id,
            reason=body.reason,
            notes=body.notes,
        )
    else:
        # Real client IP — ProxyHeadersMiddleware already rewrote X-Forwarded-For.
        ip = request.client.host if request.client else "unknown"
        ip_hash = report_service.hash_ip(ip, settings.SECRET_KEY)
        report_service.scrub_expired_ip_hashes(db, cutoff)
        if report_service.count_recent_ip_reports(db, ip_hash, cutoff) >= report_service.IP_DAILY_LIMIT:
            raise rate_limited
        report = ContentReport(
            reported_itinerary_id=itinerary.id,
            reporter_user_id=None,
            reason=body.reason,
            notes=body.notes,
            reporter_ip_hash=ip_hash,
        )

    db.add(report)
    db.commit()
    db.refresh(report)

    try:
        report_service.send_report_notification(report, itinerary, current_user, settings)
    except Exception:
        # A mail outage must never fail the report the user just filed.
        logger.exception("report notification email failed")

    return ReportAck()
