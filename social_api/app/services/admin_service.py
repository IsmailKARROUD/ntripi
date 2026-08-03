"""
services/admin_service.py — Moderation actions taken from the /admin dashboard.

Every action follows the same contract:
  1. capture a content_snapshot BEFORE mutating (evidence must reflect what the
     content looked like at action time),
  2. mutate the target,
  3. append a ModerationLog row in the SAME transaction (audit can never drift
     from the action), with a mandatory operator reason,
  4. commit once, then send any email best-effort (send_email swallows failures).

Content is never hard-deleted here: "delete" sets itineraries.deleted_at and the
stored image files are deliberately left in place — both are legal/safety evidence.
"""

from __future__ import annotations

import hashlib
import logging
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload
from sqlalchemy.orm.attributes import flag_modified

from app.models.appeal import Appeal
from app.models.content_report import ContentReport
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.models.legal_escalation import LegalEscalation
from app.models.moderation_log import ModerationLog
from app.models.stop import Stop
from app.models.text_moderation_decision import TextModerationDecision
from app.models.track import Track
from app.models.user import User
from app.services import appeal_token, email_service, refresh_token_service
from app.storage.factory import storage

logger = logging.getLogger(__name__)

TARGET_ITINERARY = "itinerary"
TARGET_USER = "user"

# Report-queue SLA thresholds (App Store UGC compliance) — the dashboard paints
# rows yellow past the first and red past the second.
SLA_WARN = timedelta(hours=12)
SLA_LATE = timedelta(hours=24)


# ---------------------------------------------------------------------------
# Snapshots + audit log
# ---------------------------------------------------------------------------

def snapshot_itinerary(itinerary: Itinerary, report: ContentReport | None = None) -> dict:
    """Evidence copy of an itinerary at action time — survives a later purge."""
    snap: dict = {
        "title": itinerary.title,
        "description": itinerary.description,
        "cover_image_url": itinerary.cover_image_url,
        "visibility": itinerary.visibility,
        "owner": {"id": str(itinerary.user_id)},
    }
    if report is not None:
        snap["report_id"] = str(report.id)
        snap["report_reason"] = report.reason
    return snap


def snapshot_user(user: User, report: ContentReport | None = None) -> dict:
    snap: dict = {
        "username": user.username,
        "display_name": user.display_name,
        "avatar_url": user.avatar_url,
        "email": user.email,
    }
    if report is not None:
        snap["report_id"] = str(report.id)
        snap["report_reason"] = report.reason
    return snap


def log_action(
    db: Session,
    admin: User,
    target_type: str,
    target_id: uuid.UUID | None,
    action: str,
    reason: str,
    snapshot: dict | None = None,
) -> ModerationLog:
    """Append an audit row. Caller commits — the log must land in the same
    transaction as the mutation it describes."""
    row = ModerationLog(
        admin_user_id=admin.id,
        target_type=target_type,
        target_id=target_id,
        action=action,
        reason=reason,
        content_snapshot=snapshot,
    )
    db.add(row)
    db.flush()  # need row.id for the appeal link before commit
    return row


def set_preserving_etag(itinerary: Itinerary, **fields) -> None:
    """Apply moderator flags without bumping updated_at.

    The whole-itinerary concurrency ETag IS updated_at, so letting the column's
    onupdate=now() fire here would 412 the owner's in-flight edit session over a
    change that touches nothing they can edit. onupdate only fires for columns
    absent from the UPDATE's SET clause, and re-assigning an identical value
    doesn't mark the attribute dirty — so flag_modified is what actually forces
    the old timestamp into the statement.
    """
    previous = itinerary.updated_at
    for name, value in fields.items():
        setattr(itinerary, name, value)
    itinerary.updated_at = previous
    flag_modified(itinerary, "updated_at")


def _resolve_report(report: ContentReport | None, resolution: str) -> None:
    if report is not None and report.resolution == "pending":
        report.resolution = resolution
        report.resolved_at = datetime.now(timezone.utc)


def report_itinerary_id(report: ContentReport) -> uuid.UUID | None:
    """The reported itinerary id, or None when the report targets a rating or a
    profile instead. Reports are polymorphic; the itinerary-specific actions
    below only apply to itinerary targets."""
    return report.target_id if report.target_type == TARGET_ITINERARY else None


# ---------------------------------------------------------------------------
# Emails (best-effort, sent after commit)
# ---------------------------------------------------------------------------

def _send_moderation_email(
    user: User,
    heading: str,
    body: str,
    log: ModerationLog | None,
    target_type: str,
    target_id: uuid.UUID | None,
) -> None:
    """Notify a user about an action against them, with an appeal link.

    Imported lazily: auth_service pulls in the whole auth stack, and admin_service
    is imported by the admin router at startup.
    """
    from app.services.auth_service import _email_html

    token = appeal_token.mint_appeal_token(
        user.id, target_type, target_id, log.id if log else None
    )
    link = appeal_token.appeal_link(token)
    email_service.send_email(
        to=user.email,
        subject=f"Ntripi — {heading}",
        html=_email_html(heading, body, "Appeal this decision", link),
    )


# ---------------------------------------------------------------------------
# Report-queue actions
# ---------------------------------------------------------------------------

def dismiss_report(db: Session, admin: User, report: ContentReport, reason: str) -> None:
    """Close a report without touching the content."""
    itinerary = (
        db.get(Itinerary, report_itinerary_id(report))
        if report_itinerary_id(report) else None
    )
    _resolve_report(report, "dismissed")
    log_action(
        db, admin, TARGET_ITINERARY, report_itinerary_id(report), "dismiss", reason,
        snapshot_itinerary(itinerary, report) if itinerary else {"report_id": str(report.id)},
    )
    db.commit()


def hide_itinerary(
    db: Session, admin: User, itinerary: Itinerary, reason: str,
    report: ContentReport | None = None,
) -> None:
    """Soft penalty — content stays visible to its author only."""
    snapshot = snapshot_itinerary(itinerary, report)
    set_preserving_etag(itinerary, hidden_at=datetime.now(timezone.utc))
    _resolve_report(report, "content_hidden")
    log_action(db, admin, TARGET_ITINERARY, itinerary.id, "hide", reason, snapshot)
    db.commit()


def unhide_itinerary(db: Session, admin: User, itinerary: Itinerary, reason: str) -> None:
    snapshot = snapshot_itinerary(itinerary)
    set_preserving_etag(itinerary, hidden_at=None)
    log_action(db, admin, TARGET_ITINERARY, itinerary.id, "unhide", reason, snapshot)
    db.commit()


def soft_delete_itinerary(
    db: Session, admin: User, itinerary: Itinerary, reason: str,
    report: ContentReport | None = None,
) -> None:
    """Hard penalty — invisible to everyone including the owner. The row and its
    stored image are intentionally preserved as evidence."""
    snapshot = snapshot_itinerary(itinerary, report)
    owner = db.get(User, itinerary.user_id)
    set_preserving_etag(itinerary, deleted_at=datetime.now(timezone.utc))
    _resolve_report(report, "content_removed")
    log = log_action(db, admin, TARGET_ITINERARY, itinerary.id, "delete", reason, snapshot)
    db.commit()

    if owner is not None:
        _send_moderation_email(
            owner,
            "Your content was removed",
            f"An itinerary you posted (“{snapshot['title']}”) was removed by a "
            f"moderator. Reason: {reason}",
            log, TARGET_ITINERARY, itinerary.id,
        )


def warn_user(
    db: Session, admin: User, user: User, reason: str,
    report: ContentReport | None = None,
) -> None:
    snapshot = snapshot_user(user, report)
    _resolve_report(report, "user_warned")
    log = log_action(db, admin, TARGET_USER, user.id, "warn", reason, snapshot)
    db.commit()

    _send_moderation_email(
        user,
        "You've received a moderation warning",
        f"A moderator reviewed your activity on Ntripi and issued a warning. "
        f"Reason: {reason}. Further violations may lead to suspension.",
        log, TARGET_USER, user.id,
    )


def deactivate_account(db: Session, user: User) -> None:
    """The suspension mechanics, with no audit row and no commit.

    is_active=False locks every authenticated request out on the spot
    (dependencies re-read the row per request → 403 account_deactivated), and
    revoking the refresh tokens stops silent renewal. Shared by ban_user and
    csam_takedown so every suspension path locks an account identically.
    """
    user.is_active = False
    refresh_token_service.revoke_all_for_user(db, user.id)


def ban_user(
    db: Session, admin: User, user: User, reason: str,
    report: ContentReport | None = None,
) -> None:
    """Suspend an account by operator decision, then tell the user how to appeal."""
    snapshot = snapshot_user(user, report)
    deactivate_account(db, user)
    _resolve_report(report, "user_banned")
    log = log_action(db, admin, TARGET_USER, user.id, "ban", reason, snapshot)
    db.commit()

    _send_moderation_email(
        user,
        "Your account has been suspended",
        f"Your Ntripi account has been suspended by a moderator. Reason: {reason}",
        log, TARGET_USER, user.id,
    )


def unban_user(db: Session, admin: User, user: User, reason: str) -> None:
    snapshot = snapshot_user(user)
    user.is_active = True
    log_action(db, admin, TARGET_USER, user.id, "unban", reason, snapshot)
    db.commit()


def bulk_resolve(
    db: Session, admin: User, report_ids: list[uuid.UUID], action: str, reason: str,
) -> int:
    """Mass dismiss/delete for spam floods. Non-pending rows are skipped silently
    (double-submitted form, or another tab already handled them)."""
    if action not in ("dismiss", "delete"):
        raise ValueError(f"unsupported bulk action: {action}")

    reports = db.execute(
        select(ContentReport).where(
            ContentReport.id.in_(report_ids),
            ContentReport.resolution == "pending",
        )
    ).scalars().all()

    handled = 0
    for report in reports:
        itinerary = (
            db.get(Itinerary, report_itinerary_id(report))
            if report_itinerary_id(report) else None
        )
        if action == "dismiss":
            _resolve_report(report, "dismissed")
            log_action(
                db, admin, TARGET_ITINERARY, report_itinerary_id(report),
                "dismiss", reason,
                snapshot_itinerary(itinerary, report) if itinerary
                else {"report_id": str(report.id)},
            )
        else:
            if itinerary is None or itinerary.deleted_at is not None:
                # Target already gone — still close the report so the queue drains.
                _resolve_report(report, "content_removed")
                handled += 1
                continue
            snapshot = snapshot_itinerary(itinerary, report)
            set_preserving_etag(itinerary, deleted_at=datetime.now(timezone.utc))
            _resolve_report(report, "content_removed")
            log_action(db, admin, TARGET_ITINERARY, itinerary.id, "delete", reason, snapshot)
        handled += 1

    db.commit()
    return handled


# ---------------------------------------------------------------------------
# Flagged-uploads queue (rows the Rekognition scan soft-flagged at upload time)
# ---------------------------------------------------------------------------

def approve_flagged(db: Session, admin: User, log_row: ImageModerationLog, reason: str) -> None:
    """Operator judged a flagged image acceptable — clear it from the queue."""
    log_row.reviewed_at = datetime.now(timezone.utc)
    itinerary = (
        db.get(Itinerary, log_row.target_itinerary_id)
        if log_row.target_itinerary_id else None
    )
    if itinerary is not None and itinerary.deleted_at is None:
        set_preserving_etag(itinerary, moderation_status="approved")

    log_action(
        db, admin,
        TARGET_ITINERARY if itinerary is not None else TARGET_USER,
        log_row.target_itinerary_id if itinerary is not None else log_row.uploader_user_id,
        "dismiss", reason,
        {"image_hash": log_row.image_hash, "target_kind": log_row.target_kind},
    )
    db.commit()


async def remove_flagged_image(
    db: Session, admin: User, log_row: ImageModerationLog, reason: str,
) -> None:
    """Take a flagged image down. Unlike content soft-delete, the *file* is
    removed here — the scan record (hash + labels) remains as the evidence."""
    log_row.reviewed_at = datetime.now(timezone.utc)
    snapshot = {"image_hash": log_row.image_hash, "target_kind": log_row.target_kind}
    key: str | None = None
    target_type = TARGET_USER
    target_id = log_row.uploader_user_id

    if log_row.target_kind == "itinerary_cover":
        itinerary = (
            db.get(Itinerary, log_row.target_itinerary_id)
            if log_row.target_itinerary_id else None
        )
        if itinerary is not None:
            snapshot["cover_image_url"] = itinerary.cover_image_url
            key = f"itineraries/{itinerary.id}.jpg"
            set_preserving_etag(
                itinerary, cover_image_url=None, moderation_status="rejected"
            )
            target_type, target_id = TARGET_ITINERARY, itinerary.id
    else:
        user = db.get(User, log_row.uploader_user_id) if log_row.uploader_user_id else None
        if user is not None:
            if log_row.target_kind == "avatar":
                snapshot["avatar_url"] = user.avatar_url
                user.avatar_url = None
                key = f"avatars/{user.id}.jpg"
            else:  # user_cover
                snapshot["cover_image_url"] = user.cover_image_url
                user.cover_image_url = None
                key = f"covers/{user.id}.jpg"

    log_action(db, admin, target_type, target_id, "delete", reason, snapshot)
    db.commit()

    if key:
        try:
            await storage().delete(key)
        except Exception:  # storage outage must not undo the committed takedown
            logger.exception("failed deleting moderated image %s", key)


# ---------------------------------------------------------------------------
# Dashboard read queries
# ---------------------------------------------------------------------------

def pending_reports(db: Session) -> list[ContentReport]:
    """Oldest first — the queue is worked FIFO against the SLA."""
    return list(db.execute(
        select(ContentReport)
        .where(ContentReport.resolution == "pending")
        .order_by(ContentReport.created_at.asc())
    ).scalars().all())


def flagged_queue(db: Session) -> list[ImageModerationLog]:
    return list(db.execute(
        select(ImageModerationLog)
        .where(
            ImageModerationLog.action == "flagged",
            ImageModerationLog.reviewed_at.is_(None),
        )
        .order_by(ImageModerationLog.created_at.asc())
    ).scalars().all())


def pending_appeals(db: Session) -> list[Appeal]:
    return list(db.execute(
        select(Appeal)
        .where(Appeal.status == "pending")
        .order_by(Appeal.created_at.asc())
    ).scalars().all())


def pending_text_flags(db: Session) -> list[TextModerationDecision]:
    """Text the classifier queued for a human. Self-harm rows carry their own
    queue_label so the template can render them differently — the appropriate
    response there is support, not a takedown."""
    return list(db.execute(
        select(TextModerationDecision)
        .where(
            TextModerationDecision.outcome == "review",
            TextModerationDecision.reviewed_at.is_(None),
        )
        .order_by(TextModerationDecision.created_at.asc())
    ).scalars().all())


def open_legal_escalations(db: Session) -> list[LegalEscalation]:
    return list(db.execute(
        select(LegalEscalation)
        .where(LegalEscalation.closed_at.is_(None))
        .order_by(LegalEscalation.created_at.asc())
    ).scalars().all())


def resolve_text_flag(
    db: Session, admin: User, decision: TextModerationDecision,
    action: str, reason: str,
) -> None:
    """Clear a text flag from the queue: approve it, or hide the content.

    Both outcomes mark the decision reviewed — an unreviewed row is a to-do, and
    leaving it set would keep the item in the queue forever.
    """
    # Lazy: moderation_actions imports this module, so a top-level import here
    # would be circular.
    from app.services import moderation_actions

    target = moderation_actions.load_target(db, decision.target_type, decision.target_id)
    decision.reviewed_at = datetime.now(timezone.utc)

    if action == "approve":
        if target is not None:
            # The moderator's judgement overrides the classifier's, so this
            # assigns rather than escalates.
            moderation_actions.set_status(decision.target_type, target, "approved")
        log_action(
            db, admin, decision.target_type, decision.target_id, "dismiss", reason,
            {"decision_id": str(decision.id)},
        )
    elif action == "hide":
        if target is None:
            db.commit()
            return
        moderation_actions.auto_hide(
            db, decision.target_type, target, action="hide", reason=reason,
        )
        # Re-stamp as an operator action: a human made this call, so the audit
        # trail must name them rather than reading as another automated hide.
        log_action(
            db, admin, decision.target_type, decision.target_id, "hide", reason,
            {"decision_id": str(decision.id)},
        )
    else:
        raise ValueError(f"unsupported text-flag action: {action}")

    db.commit()


def has_open_escalation(db: Session, report: ContentReport) -> bool:
    """True if this report's target has an unresolved legal escalation."""
    return db.execute(
        select(LegalEscalation.id).where(
            LegalEscalation.target_type == report.target_type,
            LegalEscalation.target_id == report.target_id,
            LegalEscalation.closed_at.is_(None),
        ).limit(1)
    ).first() is not None


def hide_reported_target(
    db: Session, admin: User, report: ContentReport, target, reason: str,
) -> None:
    """Hide a reported rating or profile. Itineraries have their own function
    (they also carry hidden_at and a soft-delete state)."""
    from app.services import moderation_actions  # lazy: circular otherwise

    moderation_actions.auto_hide(
        db, report.target_type, target, action="hide", reason=reason, report=report,
    )
    _resolve_report(report, "content_hidden")
    # Re-stamp as an operator action so the audit trail names the human who
    # decided, rather than reading as another automated hide.
    log_action(
        db, admin, report.target_type, report.target_id, "hide", reason,
        {"report_id": str(report.id)},
    )
    db.commit()


def close_escalation(
    db: Session, admin: User, escalation: LegalEscalation, note: str,
) -> None:
    """Close a legal escalation. The note is mandatory — this category cannot be
    silently closed, which is the whole reason the lane exists."""
    note = (note or "").strip()
    if not note:
        raise ValueError("a closure note is required")
    if escalation.closed_at is not None:
        return  # already closed (double submit / second tab)

    escalation.closed_at = datetime.now(timezone.utc)
    escalation.closed_by = admin.id
    escalation.closure_note = note
    log_action(
        db, admin, escalation.target_type, escalation.target_id, "dismiss",
        f"Legal escalation closed: {note}",
        {"escalation_id": str(escalation.id)},
    )
    db.commit()


# ---------------------------------------------------------------------------
# CSAM takedown (response to a Cloudflare CSAM Scanning Tool notice)
# ---------------------------------------------------------------------------

# Every storage key the app writes is derived from an entity UUID, so a path
# from Cloudflare's digest resolves back to an owner without any lookup table.
_KEY_FOLDERS = {
    "avatars": "avatar",
    "covers": "user_cover",
    "itineraries": "itinerary_cover",
}

# image_hash is normally a SHA-256 of the object. When Cloudflare reports a path
# whose object is already gone we have nothing to hash, and this sentinel says
# so rather than inventing a digest.
HASH_UNAVAILABLE = "unavailable"


def parse_storage_key(path: str) -> tuple[str, uuid.UUID, str] | None:
    """Turn a path from a Cloudflare notice into (target_kind, entity id, key).

    Accepts whatever the operator pastes: a full URL, a bare key, a leading
    slash, a `?v=` cache-bust suffix. Returns None if the path is not one this
    app could have written — the caller must refuse rather than guess.
    """
    candidate = (path or "").strip()
    if not candidate:
        return None
    candidate = candidate.split("?", 1)[0].split("#", 1)[0]
    if "//" in candidate:  # strip scheme + host of a full URL
        candidate = candidate.split("//", 1)[1]
        _, _, candidate = candidate.partition("/")
    candidate = candidate.lstrip("/")
    # Tolerate the filesystem era's serving prefix (/uploads/...).
    if candidate.startswith("uploads/"):
        candidate = candidate[len("uploads/"):]

    folder, _, stem = candidate.partition("/")
    kind = _KEY_FOLDERS.get(folder)
    if kind is None or not stem:
        return None
    try:
        entity_id = uuid.UUID(stem.removesuffix(".jpg"))
    except ValueError:
        return None
    return kind, entity_id, f"{folder}/{entity_id}.jpg"


async def csam_takedown(db: Session, admin: User, path: str) -> dict:
    """Action a Cloudflare CSAM notice: preserve, remove, suspend, escalate.

    Cloudflare hash-matches at the edge on content it serves, so unlike an
    upload-time scan the object already exists here. The order below is
    deliberate: the object is hashed BEFORE it is deleted, because afterwards
    that hash is the only evidence that survives.

    Raises ValueError if the path is unrecognised or its owner is gone —
    guessing at a path we did not write could suspend an unrelated account.
    Returns a summary for the operator flash message.
    """
    from app.services import moderation_actions  # lazy: circular otherwise

    parsed = parse_storage_key(path)
    if parsed is None:
        raise ValueError(
            "Unrecognised path. Expected avatars/<id>.jpg, covers/<id>.jpg, "
            "or itineraries/<id>.jpg."
        )
    target_kind, entity_id, key = parsed

    itinerary = db.get(Itinerary, entity_id) if target_kind == "itinerary_cover" else None
    user = (
        db.get(User, itinerary.user_id) if itinerary is not None
        else db.get(User, entity_id) if target_kind != "itinerary_cover"
        else None
    )
    if user is None:
        raise ValueError(f"No account owns {key} — nothing to action.")

    # Evidence first: read and hash while the object still exists.
    try:
        raw = await storage().read(key)
    except Exception:
        logger.exception("could not read %s for CSAM evidence", key)
        raw = None
    image_hash = hashlib.sha256(raw).hexdigest() if raw else HASH_UNAVAILABLE

    db.add(ImageModerationLog(
        image_hash=image_hash,
        target_kind=target_kind,
        target_itinerary_id=itinerary.id if itinerary is not None else None,
        uploader_user_id=user.id,
        # Purge-exempt (moderation_service.PRESERVED_ACTION). No raw bytes are
        # kept anywhere — the hash is the record.
        action="rejected_csam",
        labels=[{
            "name": "csam_hash_match",
            "provider": "cloudflare",
            "key": key,
            "object_present": raw is not None,
        }],
        reviewed_at=datetime.now(timezone.utc),  # actioned as it was created
    ))

    snapshot = snapshot_user(user)
    snapshot["image_hash"] = image_hash
    snapshot["storage_key"] = key

    if itinerary is not None:
        snapshot["cover_image_url"] = itinerary.cover_image_url
        # updated_at IS the concurrency ETag — a moderation write must not move it.
        set_preserving_etag(
            itinerary, cover_image_url=None, moderation_status="rejected"
        )
    elif target_kind == "avatar":
        snapshot["avatar_url"] = user.avatar_url
        user.avatar_url = None
    else:
        snapshot["cover_image_url"] = user.cover_image_url
        user.cover_image_url = None

    already_suspended = not user.is_active
    deactivate_account(db, user)
    log_action(
        db, admin, TARGET_USER, user.id, "ban",
        f"CSAM hash match reported by Cloudflare for {key} "
        f"(sha256: {image_hash}). Account suspended; image removed.",
        snapshot,
    )
    # Same lane as every other CSAM signal, and it still cannot be closed
    # without a written note naming the CyberTipline report.
    moderation_actions.escalate(db, TARGET_USER, user, source="hash_match")
    db.commit()

    # Deliberately no email to the user: a notice would tell someone whose
    # upload matched a law-enforcement corpus exactly what was detected.
    try:
        await storage().delete(key)
    except Exception:  # storage outage must not undo the committed takedown
        logger.exception("failed deleting CSAM object %s", key)

    return {
        "key": key,
        "username": user.username,
        "image_hash": image_hash,
        "object_found": raw is not None,
        "already_suspended": already_suspended,
    }


def recent_log(db: Session, limit: int = 50, offset: int = 0) -> list[ModerationLog]:
    return list(db.execute(
        select(ModerationLog)
        .order_by(ModerationLog.created_at.desc())
        .limit(limit).offset(offset)
    ).scalars().all())


def overview_counts(db: Session) -> dict:
    def _count(stmt) -> int:
        return db.execute(stmt).scalar_one() or 0

    return {
        "pending_reports": _count(
            select(func.count(ContentReport.id))
            .where(ContentReport.resolution == "pending")
        ),
        "flagged_uploads": _count(
            select(func.count(ImageModerationLog.id)).where(
                ImageModerationLog.action == "flagged",
                ImageModerationLog.reviewed_at.is_(None),
            )
        ),
        "pending_appeals": _count(
            select(func.count(Appeal.id)).where(Appeal.status == "pending")
        ),
        "hidden_itineraries": _count(
            select(func.count(Itinerary.id)).where(Itinerary.hidden_at.is_not(None))
        ),
        "deleted_itineraries": _count(
            select(func.count(Itinerary.id)).where(Itinerary.deleted_at.is_not(None))
        ),
        "banned_users": _count(
            select(func.count(User.id)).where(User.is_active.is_(False))
        ),
        "text_flags": _count(
            select(func.count(TextModerationDecision.id)).where(
                TextModerationDecision.outcome == "review",
                TextModerationDecision.reviewed_at.is_(None),
            )
        ),
        # Rendered in its own red lane — a non-zero count is not routine.
        "legal_escalations": _count(
            select(func.count(LegalEscalation.id)).where(
                LegalEscalation.closed_at.is_(None)
            )
        ),
    }


def itinerary_detail(db: Session, itinerary_id: uuid.UUID) -> dict | None:
    """Everything an operator needs to judge one itinerary — no visibility gate.

    Deliberately bypasses can_view_itinerary(): hidden/removed/only_me content is
    exactly what a moderator has to read. Returns None when the row is gone —
    log links can point at hard-deleted itineraries.
    """
    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.tracks)
            .selectinload(Track.stops)
            .selectinload(Stop.annotations),
            selectinload(Itinerary.annotations),
        )
        .where(Itinerary.id == itinerary_id)
    ).scalar_one_or_none()
    if itinerary is None:
        return None

    itinerary.tracks.sort(key=lambda t: t.rank)
    for track in itinerary.tracks:
        track.stops.sort(key=lambda s: s.rank)

    owner = db.get(User, itinerary.user_id)

    def _all(stmt) -> list:
        return list(db.execute(stmt).scalars().all())

    log_rows = _all(
        select(ModerationLog)
        .where(
            ModerationLog.target_type == TARGET_ITINERARY,
            ModerationLog.target_id == itinerary_id,
        )
        .order_by(ModerationLog.created_at.desc())
    )
    # One IN query instead of a lookup per row — ModerationLog has no ORM
    # relationship to the acting admin, only the FK.
    admin_ids = {row.admin_user_id for row in log_rows if row.admin_user_id}
    admin_names = {
        user.id: user.username
        for user in _all(select(User).where(User.id.in_(admin_ids)))
    } if admin_ids else {}

    return {
        "itinerary": itinerary,
        "owner": owner,
        "log_rows": log_rows,
        "admin_names": admin_names,
        # Resolved reports are kept too — repeat offences are the signal.
        "reports": _all(
            select(ContentReport)
            .where(
                ContentReport.target_type == TARGET_ITINERARY,
                ContentReport.target_id == itinerary_id,
            )
            .order_by(ContentReport.created_at.desc())
        ),
        "image_logs": _all(
            select(ImageModerationLog)
            .where(ImageModerationLog.target_itinerary_id == itinerary_id)
            .order_by(ImageModerationLog.created_at.desc())
        ),
        "appeals": _all(
            select(Appeal)
            .where(
                Appeal.target_type == TARGET_ITINERARY,
                Appeal.target_id == itinerary_id,
            )
            .order_by(Appeal.created_at.desc())
        ),
        # Mirrors the gate in routers/share.py — tells the template whether the
        # public share link would resolve or 404.
        "public_page_live": (
            itinerary.visibility != "only_me"
            and itinerary.hidden_at is None
            and itinerary.deleted_at is None
            and owner is not None
            and owner.is_active
        ),
    }


def sla_class(created_at: datetime) -> str:
    """CSS class for the report's time-in-queue cell (App Store UGC SLA)."""
    age = datetime.now(timezone.utc) - _as_aware(created_at)
    if age >= SLA_LATE:
        return "sla-late"
    if age >= SLA_WARN:
        return "sla-warn"
    return "sla-ok"


def humanize_age(created_at: datetime) -> str:
    age = datetime.now(timezone.utc) - _as_aware(created_at)
    hours = int(age.total_seconds() // 3600)
    if hours < 1:
        return f"{int(age.total_seconds() // 60)}m"
    if hours < 48:
        return f"{hours}h"
    return f"{hours // 24}d"


def _as_aware(value: datetime) -> datetime:
    # SQLite (tests) hands back naive datetimes; PostgreSQL is tz-aware.
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
