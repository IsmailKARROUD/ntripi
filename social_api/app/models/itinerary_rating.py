"""
models/itinerary_rating.py — One row per (itinerary, user) pair.

Each user can rate an itinerary exactly once (UNIQUE constraint on the pair).
The aggregate (rating_avg, rating_count) is stored denormalized on the
itinerary row and recalculated by recalculate_rating() after every upsert
or delete.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, SmallInteger, UniqueConstraint, func,
)
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ItineraryRating(Base):
    __tablename__ = "itinerary_ratings"

    __table_args__ = (
        # Each user rates an itinerary at most once.
        UniqueConstraint("itinerary_id", "user_id", name="uq_itinerary_rating"),
        # Stars are always 1–5.
        CheckConstraint("stars BETWEEN 1 AND 5", name="ck_rating_stars"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    itinerary_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("itineraries.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # nullable=True + ondelete='SET NULL':
    # When a user deletes their account, their rating score is retained as
    # anonymous community data (GDPR Art. 17 — anonymized data is out of scope).
    # user_id is set to NULL rather than cascading the delete.
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )

    stars: Mapped[int] = mapped_column(SmallInteger, nullable=False)

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

    def __repr__(self) -> str:
        return f"<ItineraryRating itinerary={self.itinerary_id} user={self.user_id} stars={self.stars}>"
