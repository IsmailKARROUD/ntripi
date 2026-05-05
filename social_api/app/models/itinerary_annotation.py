"""
models/itinerary_annotation.py — SQLAlchemy ORM model for itinerary-level annotations.

Annotations attached directly to an itinerary (not to a stop).
Used for general notes about the trip as a whole, e.g. "best visited in
summer" or "book accommodation at least 2 months in advance".

Design mirrors annotation.py:
  - Type is a VARCHAR CHECK constraint (not a PG ENUM).
  - ON DELETE CASCADE: deleting the itinerary removes its annotations.
  - updated_at uses onupdate=func.now().
"""

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class ItineraryAnnotation(Base):
    __tablename__ = "itinerary_annotations"

    __table_args__ = (
        CheckConstraint(
            "type IN ('advice', 'caution', 'avoid', 'info')",
            name="ck_itinerary_annotation_type",
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

    type: Mapped[str] = mapped_column(String(20), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)

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
        back_populates="annotations",
    )

    def __repr__(self) -> str:
        return f"<ItineraryAnnotation id={self.id} type={self.type!r}>"
