"""
models/image_moderation_log.py — SQLAlchemy ORM model for image_moderation_logs.

One row per Rekognition scan decision at upload time — the legal-defensibility
audit trail for automated image moderation. Rows are retained 90 days, then
deleted opportunistically on the next scan (no cron — same pattern as the
content-report IP-hash scrub). Only label names + confidences are stored, never
the raw AWS response (data minimization: cleaner to migrate providers later).

Both FKs are SET NULL + nullable so a log row survives itinerary or account
deletion. target_kind / action are constrained strings (String + CheckConstraint),
not native enums, matching the project convention.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON, CheckConstraint, DateTime, ForeignKey, String, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Single source of truth for the enum values — kept in sync with the check
# constraints below and moderation_service.
MODERATION_TARGET_KINDS = ("itinerary_cover", "avatar", "user_cover")
MODERATION_ACTIONS = ("approved", "flagged", "rejected", "error_allowed")


class ImageModerationLog(Base):
    __tablename__ = "image_moderation_logs"
    __table_args__ = (
        CheckConstraint(
            "target_kind IN ('itinerary_cover','avatar','user_cover')",
            name="ck_moderation_target_kind",
        ),
        CheckConstraint(
            "action IN ('approved','flagged','rejected','error_allowed')",
            name="ck_moderation_action",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # SHA-256 hex of the processed JPEG bytes — identifies the exact scanned
    # content even after the stored file is replaced or deleted.
    image_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    target_kind: Mapped[str] = mapped_column(String(32), nullable=False)

    # Set only for itinerary covers. Nullable + SET NULL so the audit row
    # survives itinerary deletion.
    target_itinerary_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("itineraries.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # SET NULL keeps the row for the audit trail after account deletion.
    uploader_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    action: Mapped[str] = mapped_column(String(32), nullable=False)

    # list[{"name": str, "confidence": float}] — never the full AWS response.
    labels: Mapped[list] = mapped_column(JSON, default=list, nullable=False)

    # Indexed: the 90-day retention delete filters on it.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        # Python-side default keeps SQLite (tests) string-comparable and aware.
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    def __repr__(self) -> str:
        return f"<ImageModerationLog id={self.id} target={self.target_kind!r} action={self.action!r}>"
