"""
models/moderation_log.py — SQLAlchemy ORM model for the moderation_log table.

Append-only audit trail of every operator action taken from the /admin
dashboard (dismiss / hide / delete / warn / ban + reversals + appeal decisions).
This is the legal/safety evidence record: a content_snapshot is captured at
action time so the raw text/media URLs survive even if the original row is
later hard-purged.

target_id is polymorphic (itinerary or user) with NO foreign key on purpose —
a hard user delete (delete_my_account) must NOT cascade away the evidence, and
a report whose itinerary FK was already SET-NULLed still needs a loggable row
(hence target_id is nullable). admin_user_id IS a real FK (SET NULL) so the row
outlives the admin's own account.

target_type / action are constrained strings (String + CheckConstraint), not
native enums, matching the project convention. The tuples below are the single
source of truth, mirrored by the check constraints.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON, CheckConstraint, DateTime, ForeignKey, String, Text, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Single source of truth for the enum values — kept in sync with the check
# constraints below and admin_service / appeal_service.
MODERATION_LOG_TARGET_TYPES = ("itinerary", "user")
MODERATION_LOG_ACTIONS = (
    "dismiss", "hide", "unhide", "delete", "warn", "ban", "unban",
    "appeal_restore", "appeal_uphold", "appeal_reduce",
)


class ModerationLog(Base):
    __tablename__ = "moderation_log"
    __table_args__ = (
        CheckConstraint(
            "target_type IN ('itinerary','user')",
            name="ck_moderation_log_target_type",
        ),
        CheckConstraint(
            "action IN ('dismiss','hide','unhide','delete','warn','ban','unban',"
            "'appeal_restore','appeal_uphold','appeal_reduce')",
            name="ck_moderation_log_action",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # SET NULL keeps the audit row after the admin's account is deleted.
    admin_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    target_type: Mapped[str] = mapped_column(String(16), nullable=False)

    # Polymorphic id (itinerary or user). No FK on purpose — evidence must
    # survive a hard delete of the target. Nullable for report-driven actions
    # whose itinerary FK was already SET-NULLed before the action.
    target_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
    )

    action: Mapped[str] = mapped_column(String(32), nullable=False)

    # Operator's stated reason (or the user's appeal explanation for appeal_*).
    reason: Mapped[str] = mapped_column(Text, nullable=False)

    # Raw content captured at action time (title/description/media URLs for an
    # itinerary; username/display_name/avatar for a user) — evidence that
    # outlives the source row.
    content_snapshot: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        # Python-side default keeps SQLite (tests) string-comparable and aware.
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    def __repr__(self) -> str:
        return f"<ModerationLog id={self.id} action={self.action!r} target={self.target_type}:{self.target_id}>"
