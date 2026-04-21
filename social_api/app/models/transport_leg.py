"""
models/transport_leg.py — One leg within a transit segment.

A leg is a single mode of transport (e.g. walk, metro, taxi). Several legs
make up one TransitSegment. They are ordered by position (1, 2, 3...).

Design decisions:
  - mode uses VARCHAR + CHECK constraint (not PG ENUM) — adding new modes
    requires no ALTER TYPE migration.
  - UNIQUE(segment_id, position) prevents two legs sharing the same position
    within a segment.
  - is_free / cost mirrors the Stop pattern: is_free=True means explicitly
    free, is_free=False + cost=0.00 means the user did not enter a cost.
  - Orphan legs (segment with zero legs) are forbidden. The router enforces
    this: deleting the last leg deletes the segment too.
"""

import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import (
    Boolean, CheckConstraint, DateTime, ForeignKey, Integer,
    Numeric, SmallInteger, String, Text, UniqueConstraint, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class TransportLeg(Base):
    __tablename__ = "transport_legs"

    __table_args__ = (
        UniqueConstraint("segment_id", "position", name="uq_leg_position"),
        CheckConstraint(
            "mode IN ('walk','bus','tram','metro','train','taxi','uber','bike','ferry','car')",
            name="ck_leg_mode",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    segment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("transit_segments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    position: Mapped[int] = mapped_column(SmallInteger, nullable=False)

    mode: Mapped[str] = mapped_column(String(20), nullable=False)

    line: Mapped[str | None] = mapped_column(String(30), nullable=True)
    direction: Mapped[str | None] = mapped_column(Text, nullable=True)
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

    segment: Mapped["TransitSegment"] = relationship(
        "TransitSegment",
        back_populates="legs",
    )

    def __repr__(self) -> str:
        return f"<TransportLeg id={self.id} pos={self.position} mode={self.mode!r}>"
