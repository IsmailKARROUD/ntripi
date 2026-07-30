"""
models/user_block.py — one user blocking another.

Blocking is symmetric in effect: neither party sees the other's content, and
neither can follow or interact with the other. It is one-directional in intent
though — only the blocker can lift it, and the blocked user is never told.

Both FKs CASCADE, unlike the moderation tables: a block is a personal
preference, not evidence. When either account is deleted the relationship is
meaningless and should disappear with it.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserBlock(Base):
    __tablename__ = "user_blocks"
    __table_args__ = (
        # Blocking twice is a no-op, not a second row.
        UniqueConstraint("blocker_user_id", "blocked_user_id", name="uq_user_block"),
        CheckConstraint(
            "blocker_user_id <> blocked_user_id", name="ck_no_self_block",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    blocker_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    blocked_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    def __repr__(self) -> str:
        return f"<UserBlock {self.blocker_user_id} → {self.blocked_user_id}>"
