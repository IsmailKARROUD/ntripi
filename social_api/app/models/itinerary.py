"""
models/itinerary.py — SQLAlchemy ORM model for the itineraries table.

Design decisions:
  - UUID primary key, same pattern as User and Follow models.
  - total_duration_min and total_cost are denormalized on the itinerary row
    for fast summary reads. They are recalculated by the router after every
    stop add/update/delete — never modified directly by callers.
  - safety_rating is nullable (user may skip it) and constrained to 1–5
    at the DB level with a CHECK constraint.
  - visibility defaults to 'only_me': safest option. Users explicitly open
    up access; they never accidentally expose content.
  - cover_image_url is stored as a plain URL to a file hosted on our own server.
    No external provider URLs are persisted here.
"""

import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, Integer,
    Numeric, SmallInteger, String, Text, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Itinerary(Base):
    __tablename__ = "itineraries"

    __table_args__ = (
        # Rating is either absent (NULL) or 1–5 inclusive.
        CheckConstraint(
            "safety_rating IS NULL OR safety_rating BETWEEN 1 AND 5",
            name="ck_itinerary_safety_rating",
        ),
    )

    # UUID primary key, same pattern as User model.
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # FK to the owning user. CASCADE ensures itineraries are deleted
    # automatically when a user account is deleted.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,  # Used in GET /itineraries/me — must be fast
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # URL to a user-uploaded cover image stored on our own infrastructure.
    cover_image_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Denormalized aggregates — recalculated on every stop mutation.
    total_duration_min: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False
    )
    total_cost: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00"), server_default="0.00", nullable=False
    )

    # ISO 4217 currency code, 3 characters (EUR, USD, GBP, …)
    currency: Mapped[str] = mapped_column(
        String(3), default="EUR", server_default="'EUR'", nullable=False
    )

    safety_rating: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)

    # Denormalized community-rating aggregates — recalculated by
    # recalculate_rating() in services/itinerary_access.py after every
    # ItineraryRating insert/update/delete.
    rating_avg: Mapped[float | None] = mapped_column(
        Numeric(3, 2), nullable=True, default=None
    )
    rating_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # Four-level visibility system. Defaults to 'only_me' — the safest option.
    # Valid values: 'public' | 'followers' | 'restricted' | 'only_me'
    # Logic is enforced by can_view_itinerary() in services/itinerary_access.py.
    visibility: Mapped[str] = mapped_column(
        String(20), default="only_me", server_default="'only_me'", nullable=False
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

    # Ordered relationship — stops are always returned sorted by position.
    stops: Mapped[list["Stop"]] = relationship(
        "Stop",
        back_populates="itinerary",
        cascade="all, delete-orphan",
        order_by="Stop.position",
    )

    def __repr__(self) -> str:
        return f"<Itinerary id={self.id} title={self.title!r}>"
