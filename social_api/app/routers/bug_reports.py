"""
routers/bug_reports.py — in-app bug reporting ("shake to report").

POST /bug-reports takes a message, an optional annotated screenshot, and the
device diagnostics the client could gather. It lands in the /admin/bugs queue
and emails the operator.

Deliberately separate from POST /reports: that endpoint is moderation
machinery (hide thresholds, legal escalation, distinct-reporter counting) for
content someone else published. This one is a support ticket about our own app.

Auth is optional. Someone stuck on the login screen or looking at the suspended
screen is exactly the person with the most valuable bug to report, and requiring
a token would silence them.

Multipart rather than JSON + a second upload call: two requests would leave an
orphaned object in R2 whenever the second failed, and a row pointing at nothing
whenever the first did.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile, status
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.dependencies import get_current_user_optional
from app.errors import ApiError
from app.limiter import limiter
from app.models.bug_report import BUG_CATEGORIES, BUG_PLATFORMS, BugReport
from app.models.user import User
from app.schemas.bug_report import BugReportAck
from app.services import bug_report_service
from app.services.image_service import (
    ImageProcessingError, process_and_store, process_screenshot_image,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Bug reports"])

# Diagnostics are best-effort on the client, so an unexpected value is dropped
# rather than 422'd — losing the whole report because a device string was odd
# would be a bad trade. The column check constraints are the real guard.
def _clean(value: str | None, max_length: int, allowed: tuple[str, ...] | None = None):
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    if allowed is not None and value not in allowed:
        return None
    return value[:max_length]


@router.post(
    "/bug-reports",
    response_model=BugReportAck,
    status_code=status.HTTP_201_CREATED,
    summary="Submit an in-app bug report",
)
# Lower than REPORT_RATE_LIMIT — every one of these carries an image upload.
@limiter.limit(lambda: get_settings().BUG_REPORT_RATE_LIMIT)
async def create_bug_report(
    request: Request,  # required first positional for slowapi rate limiting
    message: str = Form(..., max_length=2000),
    category: str | None = Form(default=None),
    app_version: str | None = Form(default=None),
    platform: str | None = Form(default=None),
    os_version: str | None = Form(default=None),
    device_model: str | None = Form(default=None),
    route: str | None = Form(default=None),
    locale: str | None = Form(default=None),
    theme_mode: str | None = Form(default=None),
    screenshot: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_current_user_optional),
    settings: Settings = Depends(get_settings),
) -> BugReportAck:
    message = message.strip()
    if not message:
        raise ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            code="bug_report_empty", detail="Describe what went wrong.",
        )

    # NOT passed through moderate_or_422, matching content_reports.notes and
    # appeals.user_reason: this text is only ever read by an operator, so a
    # rejection could only silence a legitimate report.
    report = BugReport(
        user_id=current_user.id if current_user else None,
        message=message,
        category=_clean(category, 16, BUG_CATEGORIES),
        app_version=_clean(app_version, 32),
        platform=_clean(platform, 16, BUG_PLATFORMS),
        os_version=_clean(os_version, 64),
        device_model=_clean(device_model, 96),
        route=_clean(route, 255),
        locale=_clean(locale, 8),
        theme_mode=_clean(theme_mode, 8),
    )
    db.add(report)
    db.flush()  # the storage key is derived from the id

    if screenshot is not None:
        raw_bytes = await screenshot.read()
        if raw_bytes:
            key = f"bug_reports/{report.id}.jpg"
            try:
                # No ModerationContext: the screenshot is never served to another
                # user, so a Rekognition reject would only drop a real bug report
                # because our own UI tripped a classifier. EXIF is still stripped.
                # cache_bust=False — each key is a fresh UUID, never reused.
                await process_and_store(
                    raw_bytes, key, process_screenshot_image, cache_bust=False,
                )
                report.screenshot_key = key
            except ImageProcessingError:
                # Keep the report. Losing the reporter's words because the
                # capture was malformed is the wrong trade.
                logger.warning(
                    "bug report %s: screenshot rejected, storing without it", report.id
                )

    db.commit()
    db.refresh(report)

    try:
        bug_report_service.send_notification(report, current_user, settings)
    except Exception:
        # A mail outage must never fail the report the user just filed.
        logger.exception("bug report notification email failed")

    return BugReportAck(id=report.id)
