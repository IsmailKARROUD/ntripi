"""
models/itinerary_allowed_user.py — SQLAlchemy ORM model for itinerary_allowed_users.

This table implements the 'restricted' visibility allowlist. Each row grants one
specific user read access to one specific itinerary.

Design decisions:
  - Composite primary key (itinerary_id, user_id) — a user appears at most once
    per itinerary in the allowlist. No accidental duplicates.
  - ON DELETE CASCADE on both FKs — if the itinerary or the user is deleted,
    the allowlist entry is cleaned up automatically.
  - No status column — presence in the table means access is granted.
    Access is revoked by deleting the row.
  - When visibility changes away from 'restricted', the allowlist rows are
    preserved. If the owner later switches back to 'restricted', the list
    is still intact.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ItineraryAllowedUser(Base):
    __tablename__ = "itinerary_allowed_users"

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

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    def __repr__(self) -> str:
        return (
            f"<ItineraryAllowedUser itinerary={self.itinerary_id} "
            f"user={self.user_id}>"
        )
