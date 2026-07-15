"""
models/saved_itinerary.py — SQLAlchemy ORM model for saved_itineraries.

This table implements the per-user "save" (bookmark) feature. Each row records
that one user has saved one itinerary for later.

Design decisions:
  - Composite primary key (itinerary_id, user_id) — a user saves an itinerary
    at most once. No accidental duplicates; re-saving is a no-op.
  - ON DELETE CASCADE on both FKs — if the itinerary or the user is deleted,
    the saved entry is cleaned up automatically.
  - No status column — presence in the table means the itinerary is saved.
    Unsaving is a row delete.
  - saved_at drives the "Saved" screen ordering (newest first). Preserved when
    an itinerary's visibility changes — filtered at read time by
    can_view_itinerary(), not deleted, so it reappears if visibility is restored.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class SavedItinerary(Base):
    __tablename__ = "saved_itineraries"

    itinerary_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("itineraries.id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )

    saved_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    def __repr__(self) -> str:
        return (
            f"<SavedItinerary itinerary={self.itinerary_id} "
            f"user={self.user_id}>"
        )
