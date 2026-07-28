"""
models/appeal.py — SQLAlchemy ORM model for the appeals table.

A user's request to review a moderation action taken against them (content
delete, warning, or ban). One active appeal per content item/action is enforced
in appeal_service (a pending row blocks a new one); a 30-day re-appeal cooldown
after an upheld decision is measured from updated_at (the decision time).

target_id is denormalized (copied from the moderation_log row) so the 1-active
and cooldown rules keep working even if moderation_log_id is later SET-NULLed.

status is a constrained string (String + CheckConstraint), matching convention.
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
# constraint below and appeal_service.
#   pending  — awaiting an operator decision
#   upheld   — action confirmed (starts the 30-day cooldown)
#   restored — action fully reversed (content/account brought back)
#   reduced  — penalty softened (ban→warn, delete→hide)
APPEAL_STATUSES = ("pending", "upheld", "restored", "reduced")


class Appeal(Base):
    __tablename__ = "appeals"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending','upheld','restored','reduced')",
            name="ck_appeal_status",
        ),
        CheckConstraint(
            "target_type IN ('itinerary','user')",
            name="ck_appeal_target_type",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # The appellant. CASCADE: if the account is hard-deleted, their appeals go
    # too (unlike moderation_log, appeals are not evidence).
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # The action being appealed (operator context for the dashboard). SET NULL
    # so a purged log row doesn't orphan-delete the appeal.
    moderation_log_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("moderation_log.id", ondelete="SET NULL"),
        nullable=True,
    )

    target_type: Mapped[str] = mapped_column(String(16), nullable=False)
    # Denormalized from the log row so the uniqueness/cooldown rules survive
    # moderation_log_id being nulled.
    target_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )

    status: Mapped[str] = mapped_column(
        String(16), default="pending", server_default="'pending'", nullable=False
    )

    user_reason: Mapped[str] = mapped_column(Text, nullable=False)
    admin_response: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    # onupdate drives the 30-day cooldown — bumped when an operator decides.
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    def __repr__(self) -> str:
        return f"<Appeal id={self.id} status={self.status!r} target={self.target_type}:{self.target_id}>"
