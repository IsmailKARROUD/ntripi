"""
models/notification.py — SQLAlchemy ORM model for in-app notifications.

A row is a structured REFERENCE to something that happened, never a rendered
sentence: (type, subtype, actor_id, entity_type, entity_id). The client builds
the text from AppLocalizations. Storing "Alice rated Kyoto 5 days" would be
wrong in the other five locales, would freeze a display name that moderation
later hides, and would need a backfill to reword.

entity_id deliberately carries NO foreign key — the reference is polymorphic
across itineraries, users and follows (same reasoning as content_reports).
A row whose entity no longer resolves renders with a null title; it does not
500 and it does not need a cleanup job.

Types are a constrained string (String + CheckConstraint) rather than a native
enum, matching the project convention (see ck_bug_report_status, ck_report_
reason). NOTIFICATION_TYPES below is the single source of truth, mirrored by
the check constraint and by the Flutter client's NotificationType.

MUTABLE_TYPES is the subset a user can switch off in settings. The preference
is checked at WRITE time by notification_service.notify — a muted type writes
no row at all, so there is nothing to filter on read.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, Index, String, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Every notification kind the backend can write.
NOTIFICATION_TYPES = (
    "follow_request",     # someone asked to follow a private account
    "new_follower",       # someone followed a public account (auto-accepted)
    "follow_accepted",    # a private account accepted my request
    "itinerary_rated",    # someone rated one of my itineraries (first time only)
    "itinerary_saved",    # someone bookmarked one of my itineraries
    "moderation_action",  # my content was hidden / auto-hidden / removed
    "itinerary_editor_added",  # an owner granted me edit rights on their itinerary
    "itinerary_viewer_added",  # an owner let me see their restricted itinerary
)

# The three a user may switch off. The rest are mandatory: a follow request the
# recipient never sees is a request that can never be answered, an author who is
# not told their content was hidden cannot appeal within the SLA, and access
# nobody knows they hold — to view or to edit — is access nobody uses.
MUTABLE_TYPES = ("follow_accepted", "itinerary_rated", "itinerary_saved")

# Maps a mutable type to its boolean column on `users`. notify() reads through
# this, so adding a mutable type is one entry here plus one column.
PREFERENCE_COLUMNS = {
    "follow_accepted": "notify_follow_accepted",
    "itinerary_rated": "notify_ratings",
    "itinerary_saved": "notify_saves",
}

# What entity_id points at. Drives the client's tap target. "rating" appears
# only on moderation_action rows and mirrors moderation_actions.TARGET_RATING —
# those all tap through to Account status regardless, so it is informational.
NOTIFICATION_ENTITY_TYPES = ("itinerary", "user", "follow", "rating")

_TYPES_SQL = ",".join(f"'{value}'" for value in NOTIFICATION_TYPES)
_ENTITY_TYPES_SQL = ",".join(f"'{value}'" for value in NOTIFICATION_ENTITY_TYPES)


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        CheckConstraint(f"type IN ({_TYPES_SQL})", name="ck_notification_type"),
        CheckConstraint(
            f"entity_type IS NULL OR entity_type IN ({_ENTITY_TYPES_SQL})",
            name="ck_notification_entity_type",
        ),
        # The only query the list endpoint runs: one user's feed, newest first.
        Index("ix_notifications_user_created", "user_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # The recipient. CASCADE: a notification is not evidence, and a deleted
    # account's feed has no reader.
    # Deliberately NOT index=True: ix_notifications_user_created below leads
    # with user_id, so a standalone index on it would be a redundant prefix.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    type: Mapped[str] = mapped_column(String(32), nullable=False)

    # The moderation action name ("hide", "auto_hide_sla", "delete", …) for
    # moderation_action rows, so a new moderation action needs no new type.
    # A plain column, not JSON — this is the only payload any type carries.
    subtype: Mapped[str | None] = mapped_column(String(40), nullable=True)

    # Who caused it. SET NULL, not CASCADE: deleting the actor must not delete
    # the recipient's history. Null for system-generated rows (moderation).
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # Polymorphic target — no FK on entity_id, see the module docstring.
    entity_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    entity_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )

    # Null = unread. Indexed because the badge polls a COUNT on it.
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True,
    )

    # Python default as well as the server default — tests run on SQLite, which
    # has no func.now() timezone awareness, and the feed sorts on this column.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
    )
