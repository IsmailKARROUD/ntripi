"""
models/stop.py — SQLAlchemy ORM model for the stops table.

Design decisions:
  - type and related enum-like fields are stored as VARCHAR with DB-level
    CHECK constraints rather than PostgreSQL ENUMs. This makes adding new
    values cheaper (no ALTER TYPE migration required).
  - Location fields (lat, lng) use NUMERIC(9, 6) — enough precision for
    ~11cm accuracy globally. Coordinates come from Nominatim (OSM) and
    are legal to store under the ODbL license.
  - is_free=True means explicitly free (e.g. public park). is_free=False
    with cost=0.00 means the user forgot to enter the cost — the UI
    distinguishes these two cases.
  - UNIQUE (itinerary_id, position) prevents two stops from sharing the
    same position index. The reorder endpoint reassigns positions atomically.
  - transit-specific fields (transport_mode, transport_line, transport_direction)
    are only populated when type='transit'. The application layer enforces this;
    the DB allows NULLs everywhere.
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


class Stop(Base):
    __tablename__ = "stops"

    __table_args__ = (
        # Two stops in the same itinerary cannot share a position.
        # The reorder endpoint reassigns all positions in one transaction.
        UniqueConstraint("itinerary_id", "position", name="uq_stop_position"),
        # Restrict the type to the four valid values.
        CheckConstraint(
            "type IN ('origin', 'waypoint', 'transit', 'destination')",
            name="ck_stop_type",
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

    # 1-based ordering index. Managed by the reorder endpoint.
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False)

    # 'origin' | 'waypoint' | 'transit' | 'destination'
    type: Mapped[str] = mapped_column(String(20), nullable=False)

    # ---------------------------------------------------------------------------
    # Location — user-authored text + OSM coordinates (ODbL, legal to store)
    # ---------------------------------------------------------------------------
    place_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    place_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    lat: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    lng: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)

    # User-selected place category (not from Google, user picks from app enum).
    # restaurant|cafe|museum|hotel|park|station|airport|beach|landmark|other
    place_type: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # ---------------------------------------------------------------------------
    # Transit-specific fields (only used when type = 'transit')
    # ---------------------------------------------------------------------------
    # walk|bus|tram|metro|train|taxi|uber|bike|ferry|car
    transport_mode: Mapped[str | None] = mapped_column(String(20), nullable=True)
    transport_line: Mapped[str | None] = mapped_column(String(30), nullable=True)
    transport_direction: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ---------------------------------------------------------------------------
    # Time and money (all user-entered)
    # ---------------------------------------------------------------------------
    duration_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cost: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00"), server_default="0.00", nullable=False
    )
    # is_free=True means explicitly free. is_free=False + cost=0.00 means
    # the user didn't enter a cost, not that it is free.
    is_free: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )

    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # ---------------------------------------------------------------------------
    # Relationships
    # ---------------------------------------------------------------------------
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

    def __repr__(self) -> str:
        return f"<Stop id={self.id} pos={self.position} type={self.type!r}>"
