"""
models/content_report.py — SQLAlchemy ORM model for content_reports.

A content report is a viewer flagging an itinerary as inappropriate. Reports
are an append-only audit trail reviewed manually by the operator (no dashboard
yet — see the moderation ticket). Both FKs are SET NULL + nullable so a report
row survives itinerary deletion or a reporter deleting their account — the
notification email already captured the details at report time.

Reason and resolution are constrained strings (String + CheckConstraint), not
native enums, matching the project convention (see ck_leg_mode). The two tuples
below are the single source of truth, reused by report_service and mirrored by
the check constraints and the Pydantic schema regex.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, String, Text, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Single source of truth for the enum values — kept in sync with the check
# constraints below and the ReportCreate regex in app/schemas/report.py.
REPORT_REASONS = ("spam", "nsfw", "violence", "hate_speech", "harassment", "copyright", "other")
REPORT_RESOLUTIONS = ("pending", "dismissed", "content_removed", "user_warned", "user_banned")


class ContentReport(Base):
    __tablename__ = "content_reports"
    __table_args__ = (
        CheckConstraint(
            "reason IN ('spam','nsfw','violence','hate_speech','harassment','copyright','other')",
            name="ck_report_reason",
        ),
        CheckConstraint(
            "resolution IN ('pending','dismissed','content_removed','user_warned','user_banned')",
            name="ck_report_resolution",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # Nullable + SET NULL so the audit row survives itinerary deletion.
    reported_itinerary_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("itineraries.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # NULL = anonymous report (from a share page) or the reporter later deleted
    # their account. SET NULL keeps the row for the audit trail either way.
    reporter_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    # HMAC of the anonymous reporter's IP — used only for the 24 h rate window,
    # then scrubbed to NULL on the next anonymous report (never stored long-term).
    reporter_ip_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        # Python-side default keeps SQLite (tests) string-comparable and aware.
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    resolution: Mapped[str] = mapped_column(
        String(32), default="pending", server_default="'pending'", nullable=False
    )

    def __repr__(self) -> str:
        return f"<ContentReport id={self.id} reason={self.reason!r} resolution={self.resolution!r}>"
