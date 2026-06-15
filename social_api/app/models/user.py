import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Integer, JSON, String, Text, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # Display form: preserves the user's original capitalization ("Ismail").
    # NOT unique — uniqueness lives on username_lower instead.
    username: Mapped[str] = mapped_column(
        String(30), nullable=False, index=True
    )

    # Canonical form for lookups and uniqueness checks (always lowercase).
    username_lower: Mapped[str] = mapped_column(
        String(30), nullable=False, unique=True, index=True
    )

    email: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False, index=True
    )

    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    # Optional free-form display name (Unicode-friendly, up to 50 chars).
    display_name: Mapped[str | None] = mapped_column(String(50), nullable=True)

    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_image_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    passport_countries: Mapped[list | None] = mapped_column(JSON, nullable=True)
    resident_country: Mapped[str | None] = mapped_column(String(2), nullable=True)
    languages: Mapped[list | None] = mapped_column(JSON, nullable=True)

    is_private: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    followers_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    following_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    tos_accepted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
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

    @property
    def name_for_display(self) -> str:
        """Returns display_name if set, else falls back to @username."""
        return self.display_name or f"@{self.username}"

    @property
    def handle(self) -> str:
        """Returns the @username form regardless of display_name."""
        return f"@{self.username}"

    def __repr__(self) -> str:
        return f"<User id={self.id} username={self.username}>"
