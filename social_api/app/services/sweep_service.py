"""
services/sweep_service.py — the periodic moderation sweep.

Three jobs, in one pass so a single scheduler trigger is all the deployment needs:

  1. SLA enforcement. A report that nobody has reviewed is auto-actioned before
     the 24 h deadline. The clock starts when the report is FILED, not when the
     sweep runs, so the threshold is 20 h by default (capped at 22): worst case
     is threshold + sweep interval, which leaves room for a couple of missed
     runs during a deploy.

  2. Post-outage re-check. Content that published as 'pending' because no
     provider answered is scanned again. This is the other half of the
     never-silently-approve promise: 'pending' is not a resting state.

  3. Housekeeping. Expired cache entries and old reviewed decisions are purged.

Every step is idempotent — running twice produces no additional effect — and a
PostgreSQL advisory lock makes concurrent runs impossible, so the HTTP endpoint,
the in-process timer, and a second container can all fire without stepping on
each other.

All times UTC. Emails are collected during the transaction and sent after the
commit, best-effort.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select, text
from sqlalchemy.orm import Session

from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.text_moderation_cache import TextModerationCache
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import (
    bug_report_service, moderation_actions, notification_service,
    text_moderation_service,
)
from app.services.moderation_email_service import build_reason, send_auto_action_email

logger = logging.getLogger(__name__)

# Arbitrary but fixed: any process taking this lock is "the sweep". Two runs
# holding it simultaneously is exactly what we are preventing.
SWEEP_LOCK_KEY = 8_215_309_471_002_117

# Bounds one run's cost — a backlog is worked off over several runs rather than
# spending an unbounded amount on a paid API in a single pass.
RECHECK_BATCH = 100
SLA_BATCH = 200


def run_moderation_sweep(db: Session, settings) -> dict:
    """Run one sweep. Returns counters (also the endpoint's response body).

    Skips immediately if another run holds the lock — the next scheduled tick
    will pick the work up, which is preferable to two runs racing.
    """
    if not _acquire_lock(db):
        logger.info("moderation sweep skipped — another run holds the lock")
        return {"skipped": "locked"}

    counters = {
        "sla_hidden": 0,
        "sla_already_hidden": 0,
        "rechecked": 0,
        "still_pending": 0,
        "recheck_hidden": 0,
        "cache_purged": 0,
        "decisions_purged": 0,
        "bug_reports_purged": 0,
        "notifications_purged": 0,
    }
    try:
        notifications: list[dict] = []
        _enforce_sla(db, settings, counters, notifications)
        _recheck_pending(db, settings, counters, notifications)
        _purge(db, settings, counters)
        db.commit()

        # After the commit: a mail outage must never roll back an action.
        for note in notifications:
            try:
                send_auto_action_email(settings=settings, **note)
            except Exception:
                logger.exception("sweep author notification failed")
    except Exception:
        db.rollback()
        raise
    finally:
        _release_lock(db)

    logger.info("moderation sweep finished: %s", counters)
    return counters


# ---------------------------------------------------------------------------
# 1. SLA enforcement
# ---------------------------------------------------------------------------

def _enforce_sla(db: Session, settings, counters: dict, notifications: list) -> None:
    """Hide content whose report is about to breach the review deadline.

    The appeal path stays open — this is a provisional action taken because we
    ran out of time, not a judgement.
    """
    deadline = datetime.now(timezone.utc) - timedelta(hours=settings.MODERATION_SLA_HOURS)

    reports = db.execute(
        select(ContentReport)
        .where(
            ContentReport.resolution == "pending",
            ContentReport.created_at < deadline,
        )
        .order_by(ContentReport.created_at.asc())  # oldest first: closest to breach
        .limit(SLA_BATCH)
    ).scalars().all()

    for report in reports:
        target = moderation_actions.load_target(db, report.target_type, report.target_id)
        if target is None:
            # Content already gone; close the report so it stops being re-scanned.
            report.resolution = "auto_hidden"
            report.resolved_at = datetime.now(timezone.utc)
            counters["sla_already_hidden"] += 1
            continue

        author = moderation_actions.target_author(db, report.target_type, target)
        label = moderation_actions.target_label(report.target_type, target)
        log = moderation_actions.auto_hide(
            db, report.target_type, target,
            action="auto_hide_sla",
            reason=build_reason("auto_hide_sla", report.reason)
            + f" Report filed {report.created_at.isoformat()}, "
            f"deadline {settings.MODERATION_SLA_HOURS}h.",
            report=report,
        )
        if log is None:
            counters["sla_already_hidden"] += 1
            continue

        counters["sla_hidden"] += 1
        if author is not None:
            notifications.append({
                "user": author,
                "action": "auto_hide_sla",
                "item_label": label,
                "category": report.reason,
                "log_id": log.id,
                "target_type": report.target_type,
                "target_id": report.target_id,
            })


# ---------------------------------------------------------------------------
# 2. Post-outage re-check
# ---------------------------------------------------------------------------

# Which text belongs to each target type — the same fields the write path scans.
def _itinerary_fields(row: Itinerary) -> dict:
    return {"title": row.title, "description": row.description}


def _rating_fields(row: ItineraryRating) -> dict:
    return {"note": row.note}


def _user_fields(row: User) -> dict:
    return {"display_name": row.display_name, "bio": row.bio}


_RECHECK_SOURCES = (
    (moderation_actions.TARGET_ITINERARY, Itinerary, _itinerary_fields),
    (moderation_actions.TARGET_RATING, ItineraryRating, _rating_fields),
    (moderation_actions.TARGET_USER, User, _user_fields),
)


def _recheck_pending(db: Session, settings, counters: dict, notifications: list) -> None:
    """Re-scan content that published unscanned during a provider outage."""
    if not text_moderation_service.is_enabled(settings):
        return

    remaining = RECHECK_BATCH
    for target_type, model, fields_of in _RECHECK_SOURCES:
        if remaining <= 0:
            break
        rows = db.execute(
            select(model)
            .where(model.moderation_status == "pending")
            .limit(remaining)
        ).scalars().all()
        remaining -= len(rows)

        for row in rows:
            # May be None for anonymized content (the author deleted their
            # account) — there is nobody to notify, but it still needs a verdict.
            author = moderation_actions.target_author(db, target_type, row)

            ctx = text_moderation_service.TextModerationContext(
                db=db, settings=settings, target_type=target_type,
                author=author, target_id=row.id, source="recheck",
            )
            try:
                text_moderation_service.moderate_fields_or_raise(fields_of(row), ctx)
            except text_moderation_service.TextModerationRejectedError as exc:
                # The content is already live, so there is no write to block —
                # take it down and tell the author instead.
                counters["rechecked"] += 1
                _hide_after_recheck(
                    db, target_type, row, author, exc.categories, counters,
                    notifications, status="rejected",
                )
                continue

            counters["rechecked"] += 1
            if ctx.status == "pending":
                # Provider still down. Leave it pending for the next run.
                counters["still_pending"] += 1
                continue

            if ctx.status == "hidden":
                _hide_after_recheck(
                    db, target_type, row, author, ["sexual/minors"], counters,
                    notifications, status="hidden",
                    escalate_decision_id=ctx.decision_id,
                )
                continue

            # 'approved' or 'flagged' — the re-check produced a real verdict, so
            # assign it rather than escalate-only: 'pending' means we never
            # actually had one to escalate from.
            moderation_actions.set_status(target_type, row, ctx.status)


def _hide_after_recheck(
    db: Session, target_type: str, row, author, categories: list[str],
    counters: dict, notifications: list, *, status: str,
    escalate_decision_id=None,
) -> None:
    """Take down content that a re-check condemned.

    `status` is 'rejected' when the verdict would have blocked the original
    write, 'hidden' for a minors escalation. Always set through auto_hide so an
    itinerary's concurrency ETag survives.
    """
    category = categories[0] if categories else None
    log = moderation_actions.auto_hide(
        db, target_type, row,
        action="auto_reject",
        reason=build_reason("auto_reject", category)
        + " Detected on re-check after a provider outage.",
        status=status,
    )
    if log is None:
        return
    counters["recheck_hidden"] += 1

    if escalate_decision_id is not None:
        moderation_actions.escalate(
            db, target_type, row, source="score", decision_id=escalate_decision_id
        )

    if author is not None:
        notifications.append({
            "user": author,
            "action": "auto_reject",
            "item_label": moderation_actions.target_label(target_type, row),
            "category": category,
            "log_id": log.id,
            "target_type": target_type,
            "target_id": row.id,
        })


# ---------------------------------------------------------------------------
# 3. Housekeeping
# ---------------------------------------------------------------------------

def _purge(db: Session, settings, counters: dict) -> None:
    now = datetime.now(timezone.utc)

    result = db.execute(
        delete(TextModerationCache).where(TextModerationCache.expires_at < now)
    )
    counters["cache_purged"] = result.rowcount or 0

    cutoff = now - timedelta(days=settings.TEXT_MODERATION_LOG_RETENTION_DAYS)
    # Unreviewed rows are the moderator queue — retention must never empty it.
    result = db.execute(
        delete(TextModerationDecision).where(
            TextModerationDecision.created_at < cutoff,
            TextModerationDecision.reviewed_at.isnot(None),
        )
    )
    counters["decisions_purged"] = result.rowcount or 0

    # Bug-report screenshots can contain a third party's data — retention is a
    # privacy duty, not housekeeping. Only closed reports are eligible.
    counters["bug_reports_purged"] = bug_report_service.purge_expired(db, settings)

    # Read notifications only — an unread one is still the recipient's only
    # notice that something happened to them.
    counters["notifications_purged"] = notification_service.purge_expired(
        db, settings
    )


# ---------------------------------------------------------------------------
# Concurrency guard
# ---------------------------------------------------------------------------

def _is_postgres(db: Session) -> bool:
    return db.get_bind().dialect.name == "postgresql"


def _acquire_lock(db: Session) -> bool:
    """Session-scoped advisory lock. SQLite (tests, local dev) has no equivalent
    and is single-process anyway, so the lock is skipped there."""
    if not _is_postgres(db):
        return True
    return bool(
        db.execute(
            text("SELECT pg_try_advisory_lock(:key)"), {"key": SWEEP_LOCK_KEY}
        ).scalar()
    )


def _release_lock(db: Session) -> None:
    if not _is_postgres(db):
        return
    try:
        db.execute(text("SELECT pg_advisory_unlock(:key)"), {"key": SWEEP_LOCK_KEY})
        db.commit()
    except Exception:
        # The lock is session-scoped, so a dropped connection releases it anyway.
        logger.exception("failed to release the moderation sweep lock")
