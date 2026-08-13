"""
services/notification_service.py — the single write seam for in-app notifications.

Every notification in the app is created by notify(). Nothing constructs a
Notification directly: the three suppression rules below (self, muted, blocked)
only hold if there is exactly one door.

notify() does db.add() and NOTHING ELSE — no commit, no flush. This breaks
deliberately from the post-commit-and-swallow pattern the email senders use
(see bug_reports.py, report_service.send_report_notification): a mail outage
must never fail the write a user just made, but a notification row belongs in
the same transaction as the event that caused it. A follow request that
committed without its notification is a request the recipient can never answer.
Callers already commit; notify() rides along.

delete_one/delete_all/purge_expired follow the same no-commit rule. Deletion is
always hard — a notification is a nudge, not evidence, and the moderation record
one may point at lives on the violations list, not on the row.
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, case, delete, func, or_, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models.itinerary import Itinerary
from app.models.notification import (
    MUTABLE_TYPES, PREFERENCE_COLUMNS, Notification,
)
from app.models.user import User
from app.services import block_service, push_service
from app.services.token_util import as_aware_utc
from app.services.user_service import public_profile_text

logger = logging.getLogger(__name__)


def notify(
    db: Session,
    *,
    user_id: uuid.UUID | None,
    type: str,
    actor: User | None = None,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    subtype: str | None = None,
) -> Notification | None:
    """Queue a notification for `user_id`. Returns None when suppressed.

    Adds to the session without committing — see the module docstring.
    """
    if user_id is None:
        return None

    # Never notify someone about their own action. Rating your own itinerary or
    # accepting a request you sent is not news.
    if actor is not None and actor.id == user_id:
        return None

    if type in MUTABLE_TYPES:
        recipient = db.get(User, user_id)
        if recipient is None:
            return None
        if not getattr(recipient, PREFERENCE_COLUMNS[type]):
            return None

    # A block cuts visibility in both directions — that includes being told the
    # blocked user did something.
    if actor is not None and block_service.is_blocked_either_way(
        db, user_id, actor.id
    ):
        return None

    notification = Notification(
        user_id=user_id,
        type=type,
        subtype=subtype,
        actor_id=actor.id if actor is not None else None,
        entity_type=entity_type,
        entity_id=entity_id,
    )
    db.add(notification)
    _queue_push(db, notification, actor)
    return notification


def _actor_name(actor: User | None, viewer_id: uuid.UUID) -> str | None:
    """How the actor should be named in a push, or None for a system row."""
    if actor is None:
        return None
    # [0] is display_name, blanked by moderation for everyone but its author.
    return public_profile_text(actor, viewer_id)[0] or f"@{actor.username}"


def _queue_push(
    db: Session, notification: Notification, actor: User | None
) -> None:
    """Stash a rendered-at-send-time snapshot for the after_commit dispatcher.

    Placed here rather than at the nine call sites so push inherits all three
    suppression rules above for free — anything notify() refused never reaches
    this line. Still only a queue: nothing is sent until the transaction that
    created the row actually commits.
    """
    settings = get_settings()
    if not push_service.is_enabled(settings):
        return

    # Resolved now, inside the transaction, because after commit these
    # attributes are expired and reading one would fire a lazy reload on a
    # session that is between transactions.
    title: str | None = None
    if notification.entity_type == "itinerary" and notification.entity_id:
        itinerary = db.get(Itinerary, notification.entity_id)
        title = itinerary.title if itinerary is not None else None

    db.info.setdefault(push_service.PENDING_KEY, []).append(
        push_service.PendingPush(
            user_id=notification.user_id,
            type=notification.type,
            subtype=notification.subtype,
            actor_id=actor.id if actor is not None else None,
            # Same moderation blanking the feed applies, and the same fallback:
            # a hidden or unset display name becomes @username, exactly as the
            # client renders it. push_i18n's localised "Someone" is reserved for
            # rows with no actor at all — using it here would make an ordinary
            # user who never set a display name anonymous.
            actor_name=_actor_name(actor, notification.user_id),
            entity_type=notification.entity_type,
            entity_id=notification.entity_id,
            entity_title=title,
        )
    )


def badge_state(
    db: Session, user_id: uuid.UUID
) -> tuple[int, datetime | None]:
    """`(unread count, newest notification's created_at)` for the bell.

    The two travel together because they answer different questions and the
    client needs both from one request: the count is the number on the badge,
    while the timestamp is the *arrival* signal. A count cannot serve as one —
    reading a notification on another device while a new one arrives leaves it
    unchanged, so an arrival would be silently masked. MAX(created_at) only ever
    moves forward, and nothing anyone reads anywhere can move it.

    One query, both aggregates. `case` rather than a FILTER clause so SQLite
    (the test DB) takes it as well as PostgreSQL; both are served by
    ix_notifications_user_created.
    """
    unread, latest = db.execute(
        select(
            func.count(case((Notification.read_at.is_(None), 1))),
            func.max(Notification.created_at),
        ).where(Notification.user_id == user_id)
    ).one()
    # SQLite hands back a naive datetime where PostgreSQL returns an aware one;
    # the client compares these across polls, so an unanchored value is useless.
    return unread or 0, as_aware_utc(latest) if latest is not None else None


def delete_one(
    db: Session, user_id: uuid.UUID, notification_id: uuid.UUID
) -> None:
    """Delete one of `user_id`'s notifications. Silent when it is already gone.

    user_id in the WHERE is the IDOR guard — matching on id alone would let
    anyone clear anyone's feed, and a 204 would not tell them they had. It also
    makes another user's id indistinguishable from a missing one, so there is no
    existence oracle. Does not commit; the caller owns the transaction.
    """
    db.execute(
        delete(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
        )
    )


def delete_all(db: Session, user_id: uuid.UUID) -> int:
    """Empty `user_id`'s feed. Returns the count. Does not commit."""
    result = db.execute(
        delete(Notification).where(Notification.user_id == user_id)
    )
    return result.rowcount or 0


def purge_expired(db: Session, settings) -> int:
    """Delete read notifications past the retention window, plus anything past
    the hard age cap regardless of read state. Returns the count.

    An unread row outlives the read window — an author who has not opened the
    app since their content was hidden still needs to find out why — but not the
    cap: a year-old notice nobody opened is not something anyone can still act
    on, and the feed would otherwise grow forever.
    """
    now = datetime.now(timezone.utc)
    read_cutoff = now - timedelta(days=settings.NOTIFICATION_RETENTION_DAYS)
    hard_cutoff = now - timedelta(days=settings.NOTIFICATION_MAX_AGE_DAYS)
    result = db.execute(
        delete(Notification).where(
            or_(
                and_(
                    Notification.read_at.is_not(None),
                    Notification.read_at < read_cutoff,
                ),
                Notification.created_at < hard_cutoff,
            )
        )
    )
    return result.rowcount or 0
