"""
models/annotation.py — SQLAlchemy ORM model for the annotations table.

Annotations are short user-written notes attached to a stop.
They are categorised by type to help readers quickly identify intent:
  - advice: helpful tip (e.g. "arrive early to avoid queues")
  - caution: something to be aware of (e.g. "busy road to cross")
  - avoid: something to skip (e.g. "overpriced tourist trap nearby")
  - info: neutral information (e.g. "wheelchair accessible")

Design decisions:
  - Type is VARCHAR with a CHECK constraint (not a PG ENUM) for the same
    reason as Stop.type — adding new types requires no ALTER TYPE migration.
  - ON DELETE CASCADE: when a stop is deleted, all its annotations are
    automatically removed. No orphaned annotation rows possible.
  - updated_at uses onupdate=func.now() so every ORM UPDATE statement
    automatically refreshes the timestamp without manual assignment.
"""

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Annotation(Base):
    __tablename__ = "annotations"

    __table_args__ = (
        CheckConstraint(
            "type IN ('advice', 'caution', 'avoid', 'info')",
            name="ck_annotation_type",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    stop_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stops.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # 'advice' | 'caution' | 'avoid' | 'info'
    type: Mapped[str] = mapped_column(String(20), nullable=False)

    # The actual user-written text. Required — an annotation without content
    # would be meaningless.
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

    # Relationship back to the stop.
    stop: Mapped["Stop"] = relationship(
        "Stop",
        back_populates="annotations",
    )

    def __repr__(self) -> str:
        return f"<Annotation id={self.id} type={self.type!r}>"
