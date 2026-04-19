"""
models/user.py — SQLAlchemy ORM model for the users table.

Design decisions:
  - UUID primary key: avoids sequential integer IDs that leak user counts,
    are harder to enumerate, and make horizontal sharding easier later.
  - Denormalized counters (followers_count, following_count):
    Reading a user profile is far more common than following/unfollowing.
    Storing counts directly on the user row means profile reads are O(1)
    instead of requiring a COUNT query on the follows table every time.
    The trade-off: we must update these counters carefully in every code path
    that changes follow relationships. This is documented and enforced in
    the follow service.
  - is_private drives the entire follow flow (see follow.py and follows router).
  - is_active enables soft-delete/suspension without losing data or breaking
    foreign key references. The get_current_user dependency checks this flag.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Integer, String, Text, DateTime, func, TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class User(Base):
    __tablename__ = "users"

    # UUID primary key. server_default generates the UUID at the DB level,
    # but we also set default=uuid.uuid4 so the Python object has an ID
    # immediately after instantiation (before flush/commit).
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # Username constraints:
    # - VARCHAR(30) limits length at the DB level (belt-and-suspenders with Pydantic).
    # - unique=True enforces uniqueness via a DB constraint, not just application code.
    # - index=True creates a B-tree index for fast lookups by username.
    # - The regex constraint (only lowercase letters, digits, underscores) is
    #   enforced at the API layer (Pydantic) to keep the DB model simple.
    username: Mapped[str] = mapped_column(
        String(30), unique=True, nullable=False, index=True
    )

    email: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False, index=True
    )

    # We never store the plain password. This column holds only the bcrypt hash.
    # bcrypt hashes are always 60 characters, but VARCHAR(255) leaves room
    # for future algorithm migrations.
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    display_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # The privacy toggle. When True:
    #   - Follow requests start as 'pending' and require approval.
    #   - Follower/following lists are hidden from non-followers.
    # When False (public):
    #   - Follow requests are immediately accepted.
    #   - All content is visible.
    # Default is True — new accounts are private until the user explicitly
    # switches to public. This protects user data by default.
    is_private: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Denormalized counters for fast profile reads.
    # These are incremented/decremented in the follow service — never directly here.
    # Using max(0, count - 1) on decrement prevents going negative due to race conditions.
    followers_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    following_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    # Soft-delete flag. Deactivated users cannot log in (checked in get_current_user).
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Timestamp when the user accepted the Terms of Service.
    # Nullable for existing users who registered before this field was added.
    # Required for all new registrations (enforced at the API layer).
    tos_accepted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    # server_default uses the DB's NOW() for the initial insert.
    # onupdate=func.now() automatically sets updated_at on every UPDATE statement.
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

    # Relationships — back_populates creates bidirectional access.
    # "sent_follows" = follow records where this user is the follower (the requester).
    # "received_follows" = follow records where this user is being followed.
    sent_follows: Mapped[list["Follow"]] = relationship(
        "Follow",
        foreign_keys="Follow.follower_id",
        back_populates="follower",
        cascade="all, delete-orphan",
    )
    received_follows: Mapped[list["Follow"]] = relationship(
        "Follow",
        foreign_keys="Follow.following_id",
        back_populates="following_user",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<User id={self.id} username={self.username}>"
