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
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.models.content_report import LEGACY_REASON_ALIASES, ContentReport
from app.models.text_moderation_decision import TextModerationDecision
from app.services import moderation_actions, moderation_policy
from app.services.email_service import send_email
from app.services.moderation_email_service import build_reason
from app.services.share_service import build_share_url

logger = logging.getLogger(__name__)

# Business rate limits (per rolling 24 h window).
USER_DAILY_LIMIT = 10
IP_DAILY_LIMIT = 3
RATE_WINDOW = timedelta(days=1)

# Reporter reputation weighting is explicitly out of scope. When it arrives it
# belongs in _effective_threshold, which is the only place that decides how many
# reporters are "enough" — nothing else needs to change.


def normalize_reason(reason: str) -> str:
    """Map a legacy wire value onto its canonical reason.

    Deployed clients still send the old vocabulary (nsfw / violence /
    copyright); rejecting those would break every app version already
    installed, so they are translated here and stored canonically.
    """
    return LEGACY_REASON_ALIASES.get(reason, reason)


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


def has_pending_report(db: Session, user_id, target_type: str, target_id) -> bool:
    """True if this user already has an unresolved report for this target — used
    to make re-reporting idempotent (no duplicate row, no duplicate email).

    This is also what makes the hide thresholds count *distinct* reporters for
    free: one person reporting five times can only ever produce one row."""
    return db.execute(
        select(ContentReport.id).where(
            ContentReport.reporter_user_id == user_id,
            ContentReport.target_type == target_type,
            ContentReport.target_id == target_id,
            ContentReport.resolution == "pending",
        ).limit(1)
    ).first() is not None


def has_pending_report_by_ip(db: Session, ip_hash: str, target_type: str, target_id) -> bool:
    """True if this anonymous IP already has an unresolved report for this target —
    used to make re-reporting idempotent (no duplicate row, no duplicate email)."""
    return db.execute(
        select(ContentReport.id).where(
            ContentReport.reporter_ip_hash == ip_hash,
            ContentReport.target_type == target_type,
            ContentReport.target_id == target_id,
            ContentReport.resolution == "pending",
        ).limit(1)
    ).first() is not None


# ---------------------------------------------------------------------------
# Distinct-reporter hide thresholds
# ---------------------------------------------------------------------------

def count_distinct_reporters(
    db: Session, target_type: str, target_id: uuid.UUID, reason: str
) -> int:
    """How many different people have an open report of this reason on this target.

    Signed-in reporters are counted by user id; anonymous ones by IP hash. Rows
    with neither (an anonymous report whose hash was already scrubbed past the
    rate window) count as one apiece — they were distinct submissions, and
    discarding them would let an attacker age out the evidence.
    """
    rows = db.execute(
        select(ContentReport.reporter_user_id, ContentReport.reporter_ip_hash).where(
            ContentReport.target_type == target_type,
            ContentReport.target_id == target_id,
            ContentReport.reason == reason,
            ContentReport.resolution == "pending",
        )
    ).all()

    identified: set[str] = set()
    anonymous_unidentifiable = 0
    for user_id, ip_hash in rows:
        if user_id is not None:
            identified.add(f"u:{user_id}")
        elif ip_hash is not None:
            identified.add(f"i:{ip_hash}")
        else:
            anonymous_unidentifiable += 1
    return len(identified) + anonymous_unidentifiable


def _classifier_corroborates(
    db: Session, target_type: str, target_id: uuid.UUID, reason: str
) -> bool:
    """True if our own classifier already suspected this content for a matching
    category — checked against the most recent decision for the target."""
    decision = db.execute(
        select(TextModerationDecision)
        .where(
            TextModerationDecision.target_type == target_type,
            TextModerationDecision.target_id == target_id,
        )
        .order_by(TextModerationDecision.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    if decision is None:
        return False
    return moderation_policy.scores_corroborate_reason(decision.scores or {}, reason)


def _effective_threshold(
    db: Session, settings, target_type: str, target, reason: str
) -> int:
    """Distinct reporters needed before this content is hidden.

    Drops by one (floor 1) when the content is already flagged, or when a
    classifier score for a matching category is above its review threshold:
    machine suspicion plus a human report is high confidence, and waiting for a
    second reporter would leave it up for no good reason.
    """
    base = settings.report_hide_thresholds.get(reason)
    if base is None:
        return 0  # unknown reason: never auto-hide, leave it to a human
    if base <= 1:
        return base

    already_flagged = getattr(target, "moderation_status", "approved") == "flagged"
    if already_flagged or _classifier_corroborates(
        db, target_type, getattr(target, "id", None), reason
    ):
        return max(1, base - 1)
    return base


@dataclass(frozen=True)
class HideOutcome:
    """What check_hide_threshold did, so the caller can email after committing."""

    hidden: bool = False
    author: object | None = None
    log_id: uuid.UUID | None = None
    item_label: str = "content"
    category: str | None = None


def check_hide_threshold(
    db: Session, settings, report: ContentReport, target
) -> HideOutcome:
    """Hide `target` if enough distinct people have reported it for this reason.

    Does not commit: the hide, its audit row, and the report resolution must land
    in one transaction. The caller commits, then notifies the author.
    """
    target_type = report.target_type
    if target is None:
        return HideOutcome()

    threshold = _effective_threshold(db, settings, target_type, target, report.reason)
    if threshold <= 0:
        return HideOutcome()  # unknown reason — leave it to a human

    reporters = count_distinct_reporters(
        db, target_type, report.target_id, report.reason
    )
    if reporters < threshold:
        return HideOutcome()

    author = moderation_actions.target_author(db, target_type, target)
    label = moderation_actions.target_label(target_type, target)
    log = moderation_actions.auto_hide(
        db, target_type, target,
        action="auto_hide_reports",
        reason=build_reason("auto_hide_reports", report.reason)
        + f" Distinct reporters: {reporters} (threshold {threshold}).",
        report=report,
    )

    if report.reason == "csam":
        # Obligations beyond hiding — must not be closable as a routine item.
        moderation_actions.escalate(
            db, target_type, target, source="report", report=report
        )

    if log is None:
        return HideOutcome()  # already hidden; nothing new to notify about
    return HideOutcome(
        hidden=True, author=author, log_id=log.id,
        item_label=label, category=report.reason,
    )


def send_report_notification(report, target, reporter, settings, *, hidden: bool = False) -> None:
    """Email the operator about a new report. Best-effort — caller swallows errors.

    Includes a ready-to-paste "no further action" SQL snippet so the operator
    can dismiss without opening the dashboard.
    """
    if not settings.OPERATOR_EMAIL:
        logger.warning(
            "content report %s filed but OPERATOR_EMAIL is unset — email skipped", report.id
        )
        return

    label = html.escape(moderation_actions.target_label(report.target_type, target))
    notes = html.escape(report.notes) if report.notes else "—"
    if reporter is not None:
        reporter_line = f"@{html.escape(reporter.username)} ({html.escape(reporter.email)})"
    else:
        reporter_line = "Anonymous (share page)"

    # Only itineraries have a public share URL; ratings and profiles are reviewed
    # in the dashboard.
    if report.target_type == moderation_actions.TARGET_ITINERARY and target is not None:
        share_url = build_share_url(target, settings)
        link_line = f'<br><a href="{share_url}">{share_url}</a>'
    else:
        link_line = ""

    dismiss_sql = (
        f"UPDATE content_reports SET resolution = 'dismissed', resolved_at = now() "
        f"WHERE id = '{report.id}';"
    )

    escalation_banner = (
        "<p style='color:#b00020'><strong>CSAM report — legally escalated.</strong> "
        "This cannot be closed as a routine moderation item.</p>"
        if report.reason == "csam" else ""
    )
    hidden_banner = (
        "<p><strong>Already hidden automatically</strong> — the distinct-reporter "
        "threshold was reached. The author has been notified and can appeal.</p>"
        if hidden else ""
    )

    body = f"""\
<h2>New content report</h2>
{escalation_banner}{hidden_banner}
<p><strong>Target:</strong> {report.target_type} — {label}{link_line}</p>
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
