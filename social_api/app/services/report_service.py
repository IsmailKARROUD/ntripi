"""
services/report_service.py — content-report rate limiting + operator email.

The spec's rate limits are per-user (10/day) and per-anonymous-IP (3/day). These
can't be expressed with slowapi's decorator (it can't switch key/limit on auth
state, and its in-memory store resets on redeploy), so they are enforced here
against the content_reports table. A coarse slowapi backstop still guards the
endpoint against floods.

Anonymous IPs are never stored raw — only an HMAC keyed on SECRET_KEY, used for
the 24 h rate window and scrubbed to NULL afterwards (see scrub_expired_ip_hashes).
"""

from __future__ import annotations

import hashlib
import hmac
import html
import logging
from datetime import datetime, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.models.content_report import ContentReport
from app.services.email_service import send_email
from app.services.share_service import build_share_url

logger = logging.getLogger(__name__)

# Business rate limits (per rolling 24 h window).
USER_DAILY_LIMIT = 10
IP_DAILY_LIMIT = 3
RATE_WINDOW = timedelta(days=1)


def hash_ip(ip: str, secret: str) -> str:
    """HMAC-SHA256 of a client IP keyed on SECRET_KEY. Never store the raw IP."""
    return hmac.new(secret.encode(), ip.encode(), hashlib.sha256).hexdigest()


def count_recent_user_reports(db: Session, user_id, cutoff: datetime) -> int:
    return db.execute(
        select(func.count())
        .select_from(ContentReport)
        .where(
            ContentReport.reporter_user_id == user_id,
            ContentReport.created_at >= cutoff,
        )
    ).scalar_one()


def count_recent_ip_reports(db: Session, ip_hash: str, cutoff: datetime) -> int:
    return db.execute(
        select(func.count())
        .select_from(ContentReport)
        .where(
            ContentReport.reporter_ip_hash == ip_hash,
            ContentReport.created_at >= cutoff,
        )
    ).scalar_one()


def scrub_expired_ip_hashes(db: Session, cutoff: datetime) -> None:
    """NULL out IP hashes older than the rate window — keeps the "IP hash never
    stored permanently" promise without a cron. Caller commits."""
    db.execute(
        update(ContentReport)
        .where(
            ContentReport.created_at < cutoff,
            ContentReport.reporter_ip_hash.is_not(None),
        )
        .values(reporter_ip_hash=None)
    )


def has_pending_report(db: Session, user_id, itinerary_id) -> bool:
    """True if this user already has an unresolved report for this itinerary —
    used to make re-reporting idempotent (no duplicate row, no duplicate email)."""
    return db.execute(
        select(ContentReport.id).where(
            ContentReport.reporter_user_id == user_id,
            ContentReport.reported_itinerary_id == itinerary_id,
            ContentReport.resolution == "pending",
        ).limit(1)
    ).first() is not None


def send_report_notification(report, itinerary, reporter, settings) -> None:
    """Email the operator about a new report. Best-effort — caller swallows errors.

    Includes a ready-to-paste "no further action" SQL snippet so the operator
    can dismiss without a dashboard.
    """
    if not settings.OPERATOR_EMAIL:
        logger.warning(
            "content report %s filed but OPERATOR_EMAIL is unset — email skipped", report.id
        )
        return

    share_url = build_share_url(itinerary, settings)
    title = html.escape(itinerary.title)
    notes = html.escape(report.notes) if report.notes else "—"
    if reporter is not None:
        reporter_line = f"@{html.escape(reporter.username)} ({html.escape(reporter.email)})"
    else:
        reporter_line = "Anonymous (share page)"

    dismiss_sql = (
        f"UPDATE content_reports SET resolution = 'dismissed', resolved_at = now() "
        f"WHERE id = '{report.id}';"
    )

    body = f"""\
<h2>New content report</h2>
<p><strong>Itinerary:</strong> {title}<br>
<a href="{share_url}">{share_url}</a></p>
<p><strong>Reporter:</strong> {reporter_line}<br>
<strong>Reason:</strong> {report.reason}<br>
<strong>Notes:</strong> {notes}<br>
<strong>Reported at:</strong> {report.created_at.isoformat()}<br>
<strong>Report id:</strong> {report.id}</p>
<hr>
<p><strong>No further action?</strong> Run:</p>
<pre>{html.escape(dismiss_sql)}</pre>
<p>Other resolutions: <code>content_removed</code> · <code>user_warned</code> · <code>user_banned</code></p>
"""

    send_email(
        settings.OPERATOR_EMAIL,
        subject=f"[Ntripi] New content report: {report.reason}",
        html=body,
    )
