"""
models/stop.py — SQLAlchemy ORM model for the stops table.

KEY CHANGES FROM THE OLD MODEL:
  Before: stops had `position` (1-based slot) and `parallel_position` (0-based
  index within a slot). Inserting between two stops required shifting every row
  at or above the target position — two-phase to avoid unique constraint
  violations during the shift.

  After: stops belong to a `track` (FK) and have a `rank` (fractional-index
  string). Inserting between two stops only touches the new row. No shift needed.

TRACK / RANK RELATIONSHIP:
  - track_id → which track (column of alternatives) this stop belongs to.
  - rank     → the stop's order within that track.
  UNIQUE(track_id, rank) ensures no two stops in the same track share a rank.

STOP ROLE (StopType):
  The concept of "origin / waypoint / arrival" is intentionally NOT stored
  here. Flutter derives it from track position at read time:
    first track → origin, last track → arrival, rest → waypoint.
  This keeps the DB simple and avoids stale role values after reordering.
  The `type` column was dropped in migration f1e2d3c4b5a6. Never add it back.

is_free vs cost=0:
  is_free=True  → explicitly free (park, public beach, etc.)
  is_free=False + cost=0.00 → user didn't fill in the cost field.
  Only non-free stops are summed into itinerary totals.
"""

import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import (
    Boolean, DateTime, ForeignKey, Integer,
    Numeric, String, Text, UniqueConstraint, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Stop(Base):
    __tablename__ = "stops"

    # UNIQUE(track_id, rank): no two stops in the same track can share a rank.
    # On a race condition two concurrent inserts might compute the same rank;
    # the endpoint catches IntegrityError and retries with freshly fetched ranks.
    __table_args__ = (
        UniqueConstraint("track_id", "rank", name="uq_stop_rank"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # itinerary_id is kept directly on stops (in addition to via track) so
    # that totals recalculation (SELECT * FROM stops WHERE itinerary_id=?) can
    # hit the index without a join to tracks.
    itinerary_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("itineraries.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Which track this stop belongs to. ON DELETE CASCADE: deleting a track
    # deletes all its stops and their annotations automatically.
    track_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tracks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Fractional-index string — position within the track.
    # TEXT COLLATE "C" is applied via ALTER TABLE in the migration.
    rank: Mapped[str] = mapped_column(String, nullable=False)

    place_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    place_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    lat: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    lng: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)

    # 11 purpose-based categories (camelCase strings):
    # eatDrink | sleep | pray | learnSee | buy | playWatch | nature |
    # travel | healBathe | entertainment | sight
    place_type: Mapped[str | None] = mapped_column(String(50), nullable=True)

    duration_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cost: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00"), server_default="0.00", nullable=False
    )
    is_free: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    itinerary: Mapped["Itinerary"] = relationship(
        "Itinerary",
        back_populates="stops",
    )

    track: Mapped["Track"] = relationship(
        "Track",
        back_populates="stops",
    )

    annotations: Mapped[list["Annotation"]] = relationship(
        "Annotation",
        back_populates="stop",
        cascade="all, delete-orphan",
        order_by="Annotation.created_at",
    )

    # The segment that DEPARTS from this stop (at most one per stop).
    # Cascade delete: removing a stop also removes its outgoing segment + legs.
    outgoing_segment: Mapped["TransitSegment | None"] = relationship(
        "TransitSegment",
        foreign_keys="TransitSegment.from_stop_id",
        back_populates="from_stop",
        uselist=False,
        cascade="all, delete-orphan",
    )

    # The segment that ARRIVES at this stop (at most one per stop).
    incoming_segment: Mapped["TransitSegment | None"] = relationship(
        "TransitSegment",
        foreign_keys="TransitSegment.to_stop_id",
        back_populates="to_stop",
        uselist=False,
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<Stop id={self.id} track={self.track_id} rank={self.rank!r}>"
