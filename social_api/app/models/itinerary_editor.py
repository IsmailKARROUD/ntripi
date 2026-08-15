"""
models/itinerary_editor.py — SQLAlchemy ORM model for itinerary_editors.

Each row grants one user the right to modify one itinerary and its subcontent.
Mirrors itinerary_allowed_users deliberately: same composite-PK shape, same
CASCADE rules, same "presence means granted" semantics.

Design decisions:
  - Composite primary key (itinerary_id, user_id) — a user appears at most once
    per itinerary. Dedupe is structural, so no unique index is needed.
  - ON DELETE CASCADE on both FKs — a grant is a preference, not evidence.
  - No status column — presence in the table means edit access is granted.
    Access is revoked by deleting the row.
  - Editing is a layer on top of visibility, never a replacement for it: a row
    here grants nothing unless can_view_itinerary() also passes. That check is
    re-run on every request, so losing view access revokes editing with no
    bookkeeping. See can_edit_itinerary() in services/itinerary_access.py.
  - granted_by is audit only and SET NULL, so removing the granting account
    never takes the grant with it.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ItineraryEditor(Base):
    __tablename__ = "itinerary_editors"

    # Unlike the allowlist, this table IS queried by the trailing column
    # ("itineraries I can edit"), which the composite PK's leading column
    # cannot serve.
    __table_args__ = (
        Index("ix_itinerary_editors_user", "user_id"),
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
        primary_key=True,
        nullable=False,
    )

    granted_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    def __repr__(self) -> str:
        return (
            f"<ItineraryEditor itinerary={self.itinerary_id} "
            f"user={self.user_id}>"
        )
