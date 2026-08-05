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
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.models.notification import (
    MUTABLE_TYPES, PREFERENCE_COLUMNS, Notification,
)
from app.models.user import User
from app.services import block_service

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
    return notification


def unread_count(db: Session, user_id: uuid.UUID) -> int:
    return db.execute(
        select(func.count(Notification.id)).where(
            Notification.user_id == user_id,
            Notification.read_at.is_(None),
        )
    ).scalar_one() or 0


def purge_expired(db: Session, settings) -> int:
    """Delete READ notifications past the retention window. Returns the count.

    Unread rows are never purged however old: an author who has not opened the
    app since their content was hidden still needs to find out why.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(
        days=settings.NOTIFICATION_RETENTION_DAYS
    )
    result = db.execute(
        delete(Notification).where(
            Notification.read_at.is_not(None),
            Notification.read_at < cutoff,
        )
    )
    return result.rowcount or 0
