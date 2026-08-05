"""
schemas/notification.py — wire shapes for the in-app notification feed.

NotificationItem carries structured references plus the *resolved* bits the
client cannot look up cheaply (actor handle, entity title). It deliberately
does NOT carry a rendered sentence — see models/notification.py for why.

actor_display_name is resolved through user_service.public_profile_text, so a
moderated display name arrives as null and the client falls back to @username.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class NotificationItem(BaseModel):
    """One row of the feed, with its actor and entity resolved."""

    id: uuid.UUID
    type: str
    subtype: str | None
    created_at: datetime
    read: bool

    # Actor — null for system rows (moderation actions) and for a deleted actor.
    actor_id: uuid.UUID | None
    actor_username: str | None
    actor_display_name: str | None
    actor_avatar_url: str | None

    # Target. entity_title is null when the entity no longer exists — the
    # reference is polymorphic and unenforced, so this is expected, not an error.
    entity_type: str | None
    entity_id: uuid.UUID | None
    entity_title: str | None

    model_config = ConfigDict(from_attributes=True)


class NotificationsResponse(BaseModel):
    """The feed page plus the badge count, so opening the screen is one call."""

    notifications: list[NotificationItem]
    unread_count: int


class UnreadCountResponse(BaseModel):
    unread_count: int


class MarkReadRequest(BaseModel):
    """Omit `ids` entirely to mark every unread notification read."""

    ids: list[uuid.UUID] | None = Field(default=None, max_length=200)
