"""
models/track.py — SQLAlchemy ORM model for the tracks table.

WHAT IS A TRACK?
  A "track" is a vertical column of parallel stop alternatives at the same
  point in a journey. For example, at night 2 of a trip the user might have
  two hotel options — "Hotel A" or "Hotel B". Both live in the same track.
  The traveller picks one; the others are alternatives.

  Tracks are ordered within an itinerary by a fractional-index `rank` string
  (see services/ordering.py). Stops within a track are also ordered by rank.

WHY NOT JUST USE position INTEGERS?
  Integer positions require shifting every row above an insertion point.
  Rank strings let us insert or reorder with a single UPDATE — no cascade.

LIFECYCLE INVARIANT:
  A track is always non-empty. The app enforces this in two ways:
    - Creating a stop with track_id=null creates a new track + stop atomically.
    - Deleting the last stop in a track also deletes the track
      (via _delete_track_if_empty in routers/itineraries.py — explicit app
      code, not a DB trigger, so the logic is visible and auditable).
  This means the DB never contains an empty track. If you see one, something
  went wrong in the deletion path.

COLLATE "C":
  The rank column is set to COLLATE "C" after creation (via ALTER TABLE in
  the migration). This forces byte-wise comparison in ORDER BY, which matches
  Python's default string sort — critical for the ordering algorithm to work
  correctly across both Python and SQL.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Track(Base):
    __tablename__ = "tracks"

    # UNIQUE(itinerary_id, rank): two tracks in the same itinerary cannot share
    # a rank. The fractional-indexing algorithm guarantees the new rank is
    # strictly between its neighbours, but on a race condition two clients might
    # compute the same rank. The constraint catches this; the endpoint retries.
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

    # Fractional-index string. TEXT COLLATE "C" is applied via ALTER TABLE in
    # the migration — SQLAlchemy's column definition alone doesn't set collation.
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

    # Stops within this track, ordered by rank so the relationship always comes
    # back pre-sorted. Individual endpoints also sort explicitly after loading
    # via selectinload (because selectinload ignores relationship order_by).
    stops: Mapped[list["Stop"]] = relationship(
        "Stop",
        back_populates="track",
        cascade="all, delete-orphan",
        order_by="Stop.rank",
    )

    def __repr__(self) -> str:
        return f"<Track id={self.id} rank={self.rank!r}>"
