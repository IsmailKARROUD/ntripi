"""
routers/notifications.py — the authenticated in-app notification feed.

GET /notifications backs the bell screen; GET /notifications/unread-count backs
the badge; POST /notifications/read clears them; the two DELETEs remove one row
or the whole feed. Notifications are written elsewhere — see
services/notification_service.notify, the only writer — so there is no POST that
creates one.

Both DELETEs are idempotent and never 404. The client removes the row on screen
first and sends the request afterwards (there is an undo window in between), so
a retry, or a row the sweep purged in the meantime, must not raise an error for
something the user already watched disappear.

The unread-count endpoint is polled, and is cheap on purpose: ETagMiddleware
hashes the JSON body, so an unchanged badge costs a 304 with no body rather
than a round-trip of data the client already has.

It answers two things, not one. `unread_count` is the number on the badge;
`latest_at` is the *arrival* signal, and the client keys its new-notification cue
off that advancing rather than off the count rising. A count cannot carry that
meaning — reading one notification on another device while a new one arrives
leaves it unchanged, silently swallowing the arrival.

Actor and entity are resolved here rather than stored on the row, in ONE query
each per page. Resolution goes through user_service.public_profile_text so a
moderated display name degrades to the @username fallback instead of leaking.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.itinerary import Itinerary
from app.models.notification import Notification
from app.models.user import User
from app.schemas.notification import (
    MarkReadRequest, NotificationItem, NotificationsResponse,
    UnreadCountResponse,
)
from app.services import notification_service
from app.services.user_service import public_profile_text

router = APIRouter(prefix="/notifications", tags=["Notifications"])


def _resolve(
    rows: list[Notification], db: Session, viewer_id: uuid.UUID
) -> list[NotificationItem]:
    """Attach actor and entity title to a page of rows — two queries, not 2N."""
    actor_ids = {r.actor_id for r in rows if r.actor_id is not None}
    actors: dict[uuid.UUID, User] = {}
    if actor_ids:
        actors = {
            u.id: u
            for u in db.execute(
                select(User).where(User.id.in_(actor_ids))
            ).scalars().all()
        }

    itinerary_ids = {
        r.entity_id for r in rows
        if r.entity_type == "itinerary" and r.entity_id is not None
    }
    titles: dict[uuid.UUID, str] = {}
    if itinerary_ids:
        titles = dict(
            db.execute(
                select(Itinerary.id, Itinerary.title)
                .where(Itinerary.id.in_(itinerary_ids))
            ).all()
        )

    items: list[NotificationItem] = []
    for row in rows:
        actor = actors.get(row.actor_id) if row.actor_id else None
        items.append(
            NotificationItem(
                id=row.id,
                type=row.type,
                subtype=row.subtype,
                created_at=row.created_at,
                read=row.read_at is not None,
                actor_id=actor.id if actor else None,
                actor_username=actor.username if actor else None,
                # Moderated display name → None → client shows @username.
                actor_display_name=(
                    public_profile_text(actor, viewer_id)[0] if actor else None
                ),
                actor_avatar_url=actor.avatar_url if actor else None,
                entity_type=row.entity_type,
                entity_id=row.entity_id,
                # Null when the itinerary is gone — the reference is polymorphic
                # and unenforced, so a missing target is expected, not an error.
                entity_title=(
                    titles.get(row.entity_id) if row.entity_id else None
                ),
            )
        )
    return items


@router.get(
    "",
    response_model=NotificationsResponse,
    summary="The current user's notification feed",
)
def list_notifications(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> NotificationsResponse:
    rows = db.execute(
        select(Notification)
        .where(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    unread, latest_at = notification_service.badge_state(db, current_user.id)
    return NotificationsResponse(
        notifications=_resolve(list(rows), db, current_user.id),
        unread_count=unread,
        latest_at=latest_at,
    )


@router.get(
    "/unread-count",
    response_model=UnreadCountResponse,
    summary="Unread notification count (badge)",
)
def get_unread_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UnreadCountResponse:
    unread, latest_at = notification_service.badge_state(db, current_user.id)
    return UnreadCountResponse(unread_count=unread, latest_at=latest_at)


@router.post(
    "/read",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Mark notifications read (all of them when `ids` is omitted)",
)
def mark_read(
    body: MarkReadRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    stmt = select(Notification).where(
        # user_id is the IDOR guard: ids alone would let anyone clear anyone's
        # badge, and the 204 would not tell them they had.
        Notification.user_id == current_user.id,
        Notification.read_at.is_(None),
    )
    if body.ids is not None:
        stmt = stmt.where(Notification.id.in_(body.ids))

    now = datetime.now(timezone.utc)
    for row in db.execute(stmt).scalars().all():
        row.read_at = now
    db.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete every notification in the current user's feed",
)
def clear_notifications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    notification_service.delete_all(db, current_user.id)
    db.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "/{notification_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete one notification",
)
def delete_notification(
    notification_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    notification_service.delete_one(db, current_user.id, notification_id)
    db.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)
