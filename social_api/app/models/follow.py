"""
models/follow.py — SQLAlchemy ORM model for the follows table.

Design decisions:
  - status ENUM ('pending', 'accepted') — only two valid states. We intentionally
    do NOT have a 'rejected' state: when a request is rejected, the record is
    deleted entirely. This lets the requester try again without obstruction, and
    avoids storing "bad" relationship data.
  - UNIQUE CONSTRAINT on (follower_id, following_id) — prevents duplicate follow
    requests at the DB level. The application layer also checks, but this is a
    safety net.
  - CHECK CONSTRAINT (follower_id != following_id) — prevents self-follows at the
    DB level. Again, application logic checks first, but the DB is the last line
    of defense.
  - ON DELETE CASCADE — if a user is deleted, all their follows (sent and received)
    are automatically removed. This keeps the follows table clean.
"""

import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    Enum as SAEnum,
    ForeignKey,
    DateTime,
    CheckConstraint,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class FollowStatus(str, enum.Enum):
    """
    Python enum for follow status.
    Inheriting from str means instances compare equal to plain strings,
    which makes JSON serialization and Pydantic validation seamless.
    """
    pending = "pending"
    accepted = "accepted"


class Follow(Base):
    __tablename__ = "follows"

    # Table-level constraints are defined here in __table_args__.
    # They cannot be defined inline on individual columns because they
    # involve multiple columns.
    __table_args__ = (
        # Prevent a user from following the same person twice.
        UniqueConstraint("follower_id", "following_id", name="uq_follower_following"),
        # Prevent self-follows at the database level.
        CheckConstraint("follower_id != following_id", name="ck_no_self_follow"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # follower_id: the user who initiated the follow request.
    # ON DELETE CASCADE: if the follower is deleted, remove this record.
    follower_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,  # Index for "who is this user following?" queries
    )

    # following_id: the user being followed (the target).
    # ON DELETE CASCADE: if the target is deleted, remove this record.
    following_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,  # Index for "who follows this user?" queries
    )

    # The follow status drives the entire hybrid follow logic.
    # pending → the target is private and hasn't approved yet.
    # accepted → the follow relationship is active.
    status: Mapped[FollowStatus] = mapped_column(
        SAEnum(FollowStatus, name="followstatus"),
        nullable=False,
        default=FollowStatus.pending,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # ORM relationships for convenient access.
    # foreign_keys must be specified explicitly because there are two FK columns
    # pointing at the same table (users), which would otherwise be ambiguous.
    follower: Mapped["User"] = relationship(
        "User",
        foreign_keys=[follower_id],
        back_populates="sent_follows",
    )
    following_user: Mapped["User"] = relationship(
        "User",
        foreign_keys=[following_id],
        back_populates="received_follows",
    )

    def __repr__(self) -> str:
        return (
            f"<Follow follower={self.follower_id} "
            f"following={self.following_id} status={self.status}>"
        )
