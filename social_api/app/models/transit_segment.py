"""
models/transit_segment.py — Transport connection between two consecutive stops.

A TransitSegment lives strictly between two adjacent stops
(from_stop.position + 1 == to_stop.position). It holds one or more
TransportLeg rows describing the chained modes of transport.

Design decisions:
  - UNIQUE(from_stop_id, to_stop_id) enforces one segment per stop pair.
  - CHECK(from_stop_id != to_stop_id) prevents self-loops.
  - ON DELETE CASCADE on both stop FKs: deleting either stop automatically
    removes the segment (and its legs via the legs cascade).
  - total_duration_min / total_cost are denormalized from the legs, updated
    by _recalculate_segment_totals() after every leg mutation.
"""

import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, Integer,
    Numeric, UniqueConstraint, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class TransitSegment(Base):
    __tablename__ = "transit_segments"

    __table_args__ = (
        UniqueConstraint("from_stop_id", "to_stop_id", name="uq_segment_stops"),
        CheckConstraint("from_stop_id != to_stop_id", name="ck_segment_different_stops"),
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

    from_stop_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stops.id", ondelete="CASCADE"),
        nullable=False,
    )

    to_stop_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stops.id", ondelete="CASCADE"),
        nullable=False,
        # from_stop_id leads uq_segment_stops; to_stop_id is covered by nothing,
        # so a stop deletion scans this table.
        index=True,
    )

    total_duration_min: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False
    )
    total_cost: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00"), server_default="0.00", nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    itinerary: Mapped["Itinerary"] = relationship(
        "Itinerary",
        back_populates="segments",
    )

    from_stop: Mapped["Stop"] = relationship(
        "Stop",
        foreign_keys=[from_stop_id],
        back_populates="outgoing_segment",
    )

    to_stop: Mapped["Stop"] = relationship(
        "Stop",
        foreign_keys=[to_stop_id],
        back_populates="incoming_segment",
    )

    legs: Mapped[list["TransportLeg"]] = relationship(
        "TransportLeg",
        back_populates="segment",
        cascade="all, delete-orphan",
        order_by="TransportLeg.position",
    )

    def __repr__(self) -> str:
        return f"<TransitSegment id={self.id} from={self.from_stop_id} to={self.to_stop_id}>"
