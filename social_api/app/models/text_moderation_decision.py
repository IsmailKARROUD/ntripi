"""
models/text_moderation_decision.py — one row per automated text-moderation call.

Two jobs:
  1. Audit — the legal-defensibility record of what the classifier decided and
     when, backing the DSA statement-of-reasons obligation.
  2. Queue — rows with outcome='review' and reviewed_at IS NULL are the
     moderator's text-flag queue (same reviewed_at convention as
     image_moderation_logs).

PRIVACY: category scores and a content hash only. No raw text, no email, no
display name — an audit row must survive account deletion while retaining
nothing personal.

target_id has NO foreign key on purpose (the moderation_log precedent): a hard
delete of the target must not cascade away the evidence that we acted.
author_user_id is a real FK with SET NULL so the row outlives the account.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON, CheckConstraint, DateTime, ForeignKey, String, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Stop / annotation / transport-leg text rolls up to its parent itinerary —
# hiding is itinerary-level, so a per-fragment status would have no read path.
TEXT_MODERATION_TARGET_TYPES = ("itinerary", "rating", "user")

# 'pending' is this table's own outcome (no provider reached), distinct from
# the four policy outcomes in moderation_policy.
TEXT_MODERATION_DECISION_OUTCOMES = (
    "approve", "review", "reject", "hide_escalate", "pending",
)

TEXT_MODERATION_SOURCES = ("write", "recheck")


class TextModerationDecision(Base):
    __tablename__ = "text_moderation_decisions"
    __table_args__ = (
        CheckConstraint(
            "target_type IN ('itinerary','rating','user')",
            name="ck_text_decision_target_type",
        ),
        CheckConstraint(
            "outcome IN ('approve','review','reject','hide_escalate','pending')",
            name="ck_text_decision_outcome",
        ),
        CheckConstraint(
            "source IN ('write','recheck')",
            name="ck_text_decision_source",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # Same value as the cache key — identifies the exact scanned text without
    # storing it, and links a decision to the verdict that produced it.
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)

    target_type: Mapped[str] = mapped_column(String(24), nullable=False)

    # Nullable: a create-time scan runs before the row it protects exists.
    target_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
    )

    # SET NULL keeps the row after account deletion (audit survives, identity does not).
    author_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    outcome: Mapped[str] = mapped_column(String(16), nullable=False)

    # {category: score}. Empty for 'pending' (no provider produced scores).
    scores: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)

    provider: Mapped[str | None] = mapped_column(String(32), nullable=True)
    model: Mapped[str | None] = mapped_column(String(64), nullable=True)

    # Which threshold policy produced this outcome — a later policy change is
    # visible in the audit trail rather than silently rewriting history.
    policy_version: Mapped[str] = mapped_column(String(8), nullable=False)

    source: Mapped[str] = mapped_column(String(16), nullable=False, default="write")

    # 'self_harm' when a self-harm category drove the review — routes to a
    # distinct queue because the appropriate response differs from abuse.
    queue_label: Mapped[str | None] = mapped_column(String(16), nullable=True)

    # NULL = still in the moderator queue. Retention purge never touches
    # unreviewed rows.
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    def __repr__(self) -> str:
        return (
            f"<TextModerationDecision id={self.id} target={self.target_type!r} "
            f"outcome={self.outcome!r}>"
        )
