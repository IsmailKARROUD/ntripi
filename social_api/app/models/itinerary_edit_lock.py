"""
models/itinerary_edit_lock.py — SQLAlchemy ORM model for itinerary_edit_locks.

One row = one live editing claim on one itinerary. Everything about the claim is
server state; the client is told what it holds and nothing more.

Design decisions:
  - itinerary_id is the PRIMARY KEY, not just a FK. "At most one holder" is then
    a database invariant rather than something application code has to remember.
  - token_hash stores only the SHA-256 of an opaque claim token (services/
    token_util.py, same threat model as refresh and email tokens). The raw token
    is returned exactly once, by the claim endpoint.
  - The token — not user_id — is what identifies the holder on the write path.
    A takeover ROTATES it, which is the whole mechanism that leaves the previous
    device unable to save while it still believes it holds the lock. A user_id
    comparison could not express that, and a check at acquire time could not
    either.
  - There is no expires_at. Staleness is derived from last_heartbeat_at against
    the configured windows at read time, so changing EDIT_LOCK_TTL_SECONDS takes
    effect immediately instead of only for claims made afterwards.
  - No ON DELETE CASCADE concerns beyond the obvious: a deleted itinerary or a
    deleted user takes the claim with it.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ItineraryEditLock(Base):
    __tablename__ = "itinerary_edit_locks"

    # last_heartbeat_at is the only column the retention purge scans.
    __table_args__ = (
        Index("ix_itinerary_edit_locks_heartbeat", "last_heartbeat_at"),
    )

    itinerary_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("itineraries.id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    # SHA-256 hex digest — 64 chars. Never the raw token.
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
    )

    last_heartbeat_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
    )

    def __repr__(self) -> str:
        return (
            f"<ItineraryEditLock itinerary={self.itinerary_id} "
            f"user={self.user_id}>"
        )
