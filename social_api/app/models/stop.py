"""
models/stop.py — SQLAlchemy ORM model for the stops table.

Design decisions:
  - type is 'origin' | 'waypoint' | 'arrival'. 'transit' was removed in
    the transit_segments refactor — transport between stops is now modelled
    as TransitSegment + TransportLeg rows.
  - Location fields (lat, lng) use NUMERIC(9, 6) — enough precision for
    ~11cm accuracy globally.
  - is_free=True means explicitly free (e.g. public park). is_free=False
    with cost=0.00 means the user forgot to enter the cost.
  - UNIQUE(itinerary_id, position) prevents two stops sharing the same
    position index. The reorder endpoint reassigns positions atomically.
  - outgoing_segment / incoming_segment expose the TransitSegment that
    starts or ends at this stop (uselist=False — at most one each).
"""

import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import (
    Boolean, DateTime, ForeignKey, Integer,
    Numeric, SmallInteger, String, Text, UniqueConstraint, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Stop(Base):
    __tablename__ = "stops"

    __table_args__ = (
        UniqueConstraint(
            "itinerary_id", "position", "parallel_position",
            name="uq_stop_position_parallel",
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

    position: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    parallel_position: Mapped[int] = mapped_column(
        SmallInteger, default=0, server_default="0", nullable=False
    )

    place_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    place_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    lat: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    lng: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)

    # eatDrink|sleep|pray|learnSee|buy|playWatch|nature|travel|healBathe|entertainment|sight
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

    annotations: Mapped[list["Annotation"]] = relationship(
        "Annotation",
        back_populates="stop",
        cascade="all, delete-orphan",
        order_by="Annotation.created_at",
    )

    # The segment that departs from this stop (at most one).
    outgoing_segment: Mapped["TransitSegment | None"] = relationship(
        "TransitSegment",
        foreign_keys="TransitSegment.from_stop_id",
        back_populates="from_stop",
        uselist=False,
        cascade="all, delete-orphan",
    )

    # The segment that arrives at this stop (at most one).
    incoming_segment: Mapped["TransitSegment | None"] = relationship(
        "TransitSegment",
        foreign_keys="TransitSegment.to_stop_id",
        back_populates="to_stop",
        uselist=False,
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<Stop id={self.id} pos={self.position}-{self.parallel_position}>"
