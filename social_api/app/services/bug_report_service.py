"""
services/bug_report_service.py — operator notification and retention for
in-app bug reports.

Two jobs, both deliberately kept out of the router:

  send_notification()  best-effort operator email, mirroring
                       report_service.send_report_notification. The caller
                       swallows exceptions — a mail outage must never fail the
                       report the user just filed.

  purge_expired()      deletes CLOSED reports older than
                       BUG_REPORT_RETENTION_DAYS along with their screenshots.
                       Driven by the moderation sweep. This is not housekeeping:
                       a screenshot can contain another user's itinerary or a
                       third party's data, so keeping them forever is a
                       liability. Open reports are never purged — nobody has
                       read them yet.
"""

from __future__ import annotations

import asyncio
import html
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.models.bug_report import BugReport
from app.services.email_service import send_email
from app.storage.factory import storage

logger = logging.getLogger(__name__)


def send_notification(report: BugReport, reporter, settings) -> None:
    """Email the operator about a new bug report. Best-effort — caller swallows."""
    if not settings.OPERATOR_EMAIL:
        logger.warning(
            "bug report %s filed but OPERATOR_EMAIL is unset — email skipped",
            report.id,
        )
        return

    # Lazy import: the auth stack is heavy and this path runs at most a few
    # times an hour (same reasoning as moderation_email_service).
    from app.services.auth_service import _email_html

    if reporter is not None:
        reporter_line = (
            f"@{html.escape(reporter.username)} ({html.escape(reporter.email)})"
        )
    else:
        reporter_line = "Signed out"

    def _field(value: str | None) -> str:
        return html.escape(value) if value else "—"

    screenshot_line = (
        f"<br><strong>Screenshot:</strong> "
        f"{html.escape(storage().public_url(report.screenshot_key))}"
        if report.screenshot_key else ""
    )

    body = f"""\
<strong>{_field(report.category)}</strong> — reported by {reporter_line}<br><br>
{html.escape(report.message)}<br><br>
<strong>App:</strong> {_field(report.app_version)} on {_field(report.platform)}<br>
<strong>Device:</strong> {_field(report.device_model)} · {_field(report.os_version)}<br>
<strong>Screen:</strong> {_field(report.route)}<br>
<strong>Locale / theme:</strong> {_field(report.locale)} · {_field(report.theme_mode)}
{screenshot_line}"""

    send_email(
        settings.OPERATOR_EMAIL,
        subject=f"[Ntripi] Bug report: {report.category or 'other'}",
        html=_email_html(
            "New bug report", body, "Open the queue",
            f"{settings.share_base_url}/admin/bugs",
        ),
    )


def purge_expired(db: Session, settings) -> int:
    """Delete closed bug reports past the retention window. Returns the count.

    Objects are deleted BEFORE the rows: a storage failure then leaves the row
    behind so the next sweep retries it, rather than orphaning a screenshot
    nothing points at any more.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(
        days=settings.BUG_REPORT_RETENTION_DAYS
    )
    rows = db.execute(
        select(BugReport.id, BugReport.screenshot_key).where(
            BugReport.status == "closed",
            BugReport.closed_at.isnot(None),
            BugReport.closed_at < cutoff,
        )
    ).all()
    if not rows:
        return 0

    purgeable_ids = []
    for report_id, key in rows:
        if key and not _delete_object(key):
            continue  # keep the row so the next sweep retries the object
        purgeable_ids.append(report_id)

    if not purgeable_ids:
        return 0

    result = db.execute(delete(BugReport).where(BugReport.id.in_(purgeable_ids)))
    return result.rowcount or 0


def _delete_object(key: str) -> bool:
    """Best-effort storage delete from sync code. True when the object is gone.

    asyncio.run is safe here: the sweep only ever runs on a worker thread (the
    FastAPI threadpool, or asyncio.to_thread from the in-process timer), so
    there is never a loop already running on this thread.
    """
    try:
        asyncio.run(storage().delete(key))
        return True
    except Exception:
        logger.exception("failed to delete bug-report screenshot %r", key)
        return False
