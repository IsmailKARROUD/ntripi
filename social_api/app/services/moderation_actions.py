"""
services/moderation_actions.py — automated moderation actions on any target.

The shared machinery behind every action with no human actor: the
distinct-reporter threshold hide (report_service), the SLA-deadline hide and the
post-outage re-check (sweep_service), and CSAM escalation — including the one
raised by admin_service.csam_takedown, which has a human actor for the takedown
but still opens its escalation through here. Keeping it in one place means all
of them agree on the three rules that matter:

  1. An itinerary hidden from outside its owner's own request goes through
     admin_service.set_preserving_etag. Bumping updated_at would 412 the owner's
     open editor over a change they cannot see.
  2. Exactly one audit row per action, written in the same transaction, with
     admin_user_id NULL and content_snapshot NULL — automated rows hold no raw
     content.
  3. Every step is idempotent. Re-running a sweep must not re-hide, re-log, or
     re-email; the "already hidden" check is what makes that true.

Author notification is sent by the caller AFTER its commit (mail is best-effort
and must never roll back the action).
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.legal_escalation import LegalEscalation
from app.models.moderation_log import ModerationLog
from app.models.user import User
from app.services import admin_service
from app.services.itinerary_access import recalculate_rating

logger = logging.getLogger(__name__)

TARGET_ITINERARY = "itinerary"
TARGET_RATING = "rating"
TARGET_USER = "user"

_MODELS = {
    TARGET_ITINERARY: Itinerary,
    TARGET_RATING: ItineraryRating,
    TARGET_USER: User,
}


def load_target(db: Session, target_type: str, target_id: uuid.UUID | None):
    """Fetch a polymorphic target, or None if it is gone. target_id has no FK,
    so a purged target is an expected outcome, not an error."""
    model = _MODELS.get(target_type)
    if model is None or target_id is None:
        return None
    return db.get(model, target_id)


def target_author(db: Session, target_type: str, target) -> User | None:
    """The user who wrote the content — who gets notified and who may appeal."""
    if target is None:
        return None
    if target_type == TARGET_ITINERARY:
        return db.get(User, target.user_id)
    if target_type == TARGET_RATING:
        return db.get(User, target.user_id) if target.user_id else None
    if target_type == TARGET_USER:
        return target
    return None


def target_label(target_type: str, target) -> str:
    """Short human label for the notification email and the dashboard. Never used
    in an audit row."""
    if target is None:
        return "content"
    if target_type == TARGET_ITINERARY:
        return target.title
    if target_type == TARGET_RATING:
        return "your review"
    if target_type == TARGET_USER:
        return "your profile"
    return "content"


def is_hidden(target_type: str, target) -> bool:
    """True if this target is already taken down — the idempotency guard for
    every auto-hide path."""
    if target is None:
        return True  # nothing to do; treat as already actioned
    if target_type == TARGET_ITINERARY:
        return target.hidden_at is not None or target.deleted_at is not None
    return target.moderation_status in ("hidden", "rejected")


def set_status(target_type: str, target, status: str) -> None:
    """Write a content state from outside the author's own request.

    For itineraries this must not touch updated_at — that column IS the
    concurrency ETag, and moving it would 412 the author's open editor over a
    moderation change they cannot see. Other targets have no ETag.
    """
    if target_type == TARGET_ITINERARY:
        admin_service.set_preserving_etag(target, moderation_status=status)
    else:
        target.moderation_status = status


def log_system_action(
    db: Session,
    target_type: str,
    target_id: uuid.UUID | None,
    action: str,
    reason: str,
) -> ModerationLog:
    """Append an audit row for an action with no human actor.

    snapshot is always None: an automated row records structured facts in
    `reason` and nothing else, so the audit trail holds no raw content text,
    email addresses, or display names. Caller commits.
    """
    row = ModerationLog(
        admin_user_id=None,
        target_type=target_type,
        target_id=target_id,
        action=action,
        reason=reason,
        content_snapshot=None,
    )
    db.add(row)
    db.flush()  # need row.id to mint the appeal link before commit
    return row


def auto_hide(
    db: Session,
    target_type: str,
    target,
    *,
    action: str,
    reason: str,
    report: ContentReport | None = None,
    status: str = "hidden",
) -> ModerationLog | None:
    """Hide `target` and audit it. Returns the log row, or None if it was already
    hidden (making a repeat run a genuine no-op).

    `status` is the content state to record — 'hidden' for a takedown pending
    review, 'rejected' when a classifier verdict condemned it outright. It must
    be set through this function for itineraries: assigning the column directly
    would bump updated_at and 412 the author's open editor.

    Does NOT commit — the caller owns the transaction so the hide, the audit row,
    and any report resolution land together.
    """
    if is_hidden(target_type, target):
        # Still close the report: the content is down, which is what the reporter
        # asked for, and leaving it pending would keep tripping the SLA sweep.
        if report is not None and report.resolution == "pending":
            admin_service._resolve_report(report, "auto_hidden")
        return None

    now = datetime.now(timezone.utc)

    if target_type == TARGET_ITINERARY:
        # Never bump updated_at from a moderation write — see module docstring.
        admin_service.set_preserving_etag(
            target, hidden_at=now, moderation_status=status
        )
    else:
        target.moderation_status = status
        if target_type == TARGET_RATING:
            # A hidden rating leaves the averages, so they need recomputing.
            itinerary = db.get(Itinerary, target.itinerary_id)
            if itinerary is not None:
                db.flush()
                recalculate_rating(itinerary, db)

    if report is not None:
        admin_service._resolve_report(report, "auto_hidden")

    return log_system_action(db, target_type, _target_id(target_type, target), action, reason)


def escalate(
    db: Session,
    target_type: str,
    target,
    *,
    source: str,
    report: ContentReport | None = None,
    decision_id: uuid.UUID | None = None,
) -> LegalEscalation | None:
    """Open a legal-escalation row for a CSAM signal, unless one is already open.

    The caller is expected to have hidden the content already; this only records
    that the item needs review beyond a routine takedown. Deliberately does not
    report to any authority — see the model docstring.
    """
    target_id = _target_id(target_type, target)
    existing = db.execute(
        select(LegalEscalation).where(
            LegalEscalation.target_type == target_type,
            LegalEscalation.target_id == target_id,
            LegalEscalation.closed_at.is_(None),
        ).limit(1)
    ).scalar_one_or_none()
    if existing is not None:
        return existing

    row = LegalEscalation(
        target_type=target_type,
        target_id=target_id,
        source=source,
        report_id=report.id if report is not None else None,
        decision_id=decision_id,
    )
    db.add(row)
    log_system_action(
        db, target_type, target_id, "legal_escalate",
        f"Escalated for legal review (source: {source}). "
        "Cannot be closed as a routine moderation item.",
    )
    logger.warning(
        "legal escalation opened for %s:%s (source=%s)", target_type, target_id, source
    )
    return row


def _target_id(target_type: str, target) -> uuid.UUID | None:
    return getattr(target, "id", None) if target is not None else None
