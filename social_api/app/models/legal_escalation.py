"""
models/legal_escalation.py — CSAM signals that cannot be closed as routine.

A row here means content was hidden AND flagged for legal review: a user
reported it as `csam`, the classifier scored above threshold on `sexual/minors`,
or an upload matched a known-CSAM hash corpus (in which case the target is the
uploader's account — the image was rejected, never stored, so there is no
content row to point at). Belgian law imposes obligations beyond taking the content down,
so the dashboard renders these in their own lane, visually distinct from the
routine queue, and the ordinary "dismiss" action refuses to touch them —
closing one requires the dedicated route and a written note.

Deliberately NOT implemented here: automated reporting to authorities. The
requirement is that this category cannot be silently closed, not that the app
files reports on its own.

target_id has no FK (evidence survives a hard delete of the content); report_id
and decision_id are real FKs with SET NULL so the escalation outlives whichever
signal raised it.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, String, Text, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

ESCALATION_TARGET_TYPES = ("itinerary", "rating", "user")
# human report · classifier score · known-CSAM hash match at upload
ESCALATION_SOURCES = ("report", "score", "hash_match")

_SOURCES_SQL = ",".join(f"'{source}'" for source in ESCALATION_SOURCES)


class LegalEscalation(Base):
    __tablename__ = "legal_escalations"
    __table_args__ = (
        CheckConstraint(
            "target_type IN ('itinerary','rating','user')",
            name="ck_escalation_target_type",
        ),
        CheckConstraint(
            f"source IN ({_SOURCES_SQL})",
            name="ck_escalation_source",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    target_type: Mapped[str] = mapped_column(String(16), nullable=False)
    target_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
    )

    source: Mapped[str] = mapped_column(String(16), nullable=False)

    report_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("content_reports.id", ondelete="SET NULL"),
        nullable=True,
    )
    decision_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("text_moderation_decisions.id", ondelete="SET NULL"),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    # NULL = still open. Closing requires closure_note — enforced in the service,
    # not the schema, so the dashboard can report *why* it refused.
    closed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    closed_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    closure_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    def __repr__(self) -> str:
        state = "open" if self.closed_at is None else "closed"
        return f"<LegalEscalation id={self.id} {self.target_type}:{self.target_id} {state}>"
