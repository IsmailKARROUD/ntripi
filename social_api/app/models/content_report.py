"""
models/content_report.py — SQLAlchemy ORM model for content_reports.

A content report is a viewer flagging user content as inappropriate. Reports are
append-only; the operator reviews them from /admin, and the distinct-reporter
thresholds in report_service can hide content before a human looks.

The target is polymorphic (itinerary / rating / user) via target_type +
target_id, with NO foreign key on target_id — the same evidence rule as
moderation_log: a hard delete of the reported content must not cascade away the
record that it was reported. reporter_user_id IS a real FK (SET NULL) so the row
survives the reporter deleting their account.

Reason and resolution are constrained strings (String + CheckConstraint), not
native enums, matching the project convention (see ck_leg_mode). The tuples
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

# What can be reported. Stops, annotations and transport legs report as their
# parent itinerary (the client notes which fragment) — hiding is itinerary-level,
# so a sub-target would have no read path to enforce.
REPORT_TARGET_TYPES = ("itinerary", "rating", "user")

# Canonical reasons, ordered most → least severe. Each maps to a
# distinct-reporter hide threshold in REPORT_HIDE_THRESHOLDS.
REPORT_REASONS = (
    "csam", "sexual_content", "violence_threat",
    "hate_speech", "harassment", "other", "spam",
)

# Wire values from clients that predate the canonical list. Accepted on input
# and normalized before storage (report_service.normalize_reason) so a deployed
# app keeps working after a server-side rename.
LEGACY_REASON_ALIASES = {
    "nsfw": "sexual_content",
    "violence": "violence_threat",
    "copyright": "other",
}

# content_hidden is distinct from content_removed — hide keeps the content
# owner-visible, so mapping it to "removed" would make the audit trail lie.
# auto_hidden is distinct from both: it records that no human acted.
REPORT_RESOLUTIONS = (
    "pending", "dismissed", "content_removed", "content_hidden",
    "user_warned", "user_banned", "auto_hidden",
)

_REASONS_SQL = ",".join(f"'{reason}'" for reason in REPORT_REASONS)
_RESOLUTIONS_SQL = ",".join(f"'{value}'" for value in REPORT_RESOLUTIONS)


class ContentReport(Base):
    __tablename__ = "content_reports"
    __table_args__ = (
        CheckConstraint(
            "target_type IN ('itinerary','rating','user')",
            name="ck_report_target_type",
        ),
        CheckConstraint(
            f"reason IN ({_REASONS_SQL})",
            name="ck_report_reason",
        ),
        CheckConstraint(
            f"resolution IN ({_RESOLUTIONS_SQL})",
            name="ck_report_resolution",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    target_type: Mapped[str] = mapped_column(String(16), nullable=False)

    # Polymorphic id. No FK on purpose — evidence must survive a hard delete of
    # the reported content (moderation_log precedent). Nullable so a row whose
    # target was purged is still loggable.
    target_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
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
        # Indexed: the SLA sweep scans for reports older than the deadline.
        index=True,
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    resolution: Mapped[str] = mapped_column(
        String(32), default="pending", server_default="'pending'", nullable=False
    )

    def __repr__(self) -> str:
        return (
            f"<ContentReport id={self.id} target={self.target_type}:{self.target_id} "
            f"reason={self.reason!r} resolution={self.resolution!r}>"
        )
