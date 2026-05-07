"""
models/track.py — SQLAlchemy ORM model for the tracks table.

A track is a vertical column of parallel stop alternatives at the same point
in the journey (e.g. "Hotel A or Hotel B" at night 2). Tracks are ordered
within an itinerary by their fractional-index rank column.

Design decisions:
  - tracks are never empty in the DB: creating a stop with track_id=null
    creates a new track + the stop atomically; deleting the last stop in
    a track also deletes the track (app-level cascade, not DB-level, so
    the logic is auditable).
  - rank uses TEXT COLLATE "C" so PostgreSQL sorts by byte value, identical
    to Python's default string comparison and the ordering algorithm.
  - UNIQUE(itinerary_id, rank) prevents two tracks at the same rank.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Track(Base):
    __tablename__ = "tracks"

    __table_args__ = (
        UniqueConstraint("itinerary_id", "rank", name="uq_track_rank"),
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

    rank: Mapped[str] = mapped_column(String, nullable=False)

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

    itinerary: Mapped["Itinerary"] = relationship(
        "Itinerary",
        back_populates="tracks",
    )

    stops: Mapped[list["Stop"]] = relationship(
        "Stop",
        back_populates="track",
        cascade="all, delete-orphan",
        order_by="Stop.rank",
    )

    def __repr__(self) -> str:
        return f"<Track id={self.id} rank={self.rank!r}>"
