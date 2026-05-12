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
    CheckConstraint, DateTime, ForeignKey, SmallInteger, Text, UniqueConstraint, func,
)
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ItineraryRating(Base):
    __tablename__ = "itinerary_ratings"

    __table_args__ = (
        UniqueConstraint("itinerary_id", "user_id", name="uq_itinerary_rating"),
        CheckConstraint("stars BETWEEN 1 AND 5", name="ck_rating_stars"),
        CheckConstraint(
            "safety_stars IS NULL OR safety_stars BETWEEN 1 AND 5",
            name="ck_rating_safety_stars",
        ),
        CheckConstraint(
            "experience_stars IS NULL OR experience_stars BETWEEN 1 AND 5",
            name="ck_rating_experience_stars",
        ),
        CheckConstraint(
            "accessibility_stars IS NULL OR accessibility_stars BETWEEN 1 AND 5",
            name="ck_rating_accessibility_stars",
        ),
        CheckConstraint(
            "family_friendly_stars IS NULL OR family_friendly_stars BETWEEN 1 AND 5",
            name="ck_rating_family_friendly_stars",
        ),
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

    # Optional sub-ratings — collected via the "Want to share more?" dialog section.
    safety_stars: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    experience_stars: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    accessibility_stars: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    family_friendly_stars: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)

    # Optional free-text review note (Markdown source). Rendered client-side
    # with link-inert config (no clickable URLs) to keep the surface free of
    # phishing vectors on public itineraries.
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

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
