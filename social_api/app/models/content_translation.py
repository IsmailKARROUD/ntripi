"""
models/content_translation.py — machine translations of user-written text.

One row per (content, field, target language, version of the source text). The
source text itself is never stored here, only its hash: an edit makes the old
translation unreachable, and translation_service.sync_translations deletes it
in the same transaction. A translation of a given text is shared by every
viewer who asks for that language.

content_id has NO foreign key — the key is polymorphic across six tables (the
moderation_log precedent). itinerary_id is a real FK, because every
translatable row belongs to exactly one itinerary: deleting a trip, or an
account, cascades its translations away in the database, so no delete path can
forget them. Deletes below the itinerary (a stop, an annotation, a review, a
leg) go through translation_service.purge_orphans.

PRIVACY: no user reference. A translation is derived from content and lives
exactly as long as that content does.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, Text, UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Kept in sync with translation_service.REGISTRY, which is what maps each type
# to its table and fields.
TRANSLATION_CONTENT_TYPES = (
    "itinerary", "itinerary_annotation", "stop", "stop_annotation",
    "rating", "transport_leg",
)
TRANSLATION_FIELDS = (
    "title", "description", "recommended_period_note", "content", "notes", "note",
)


def _in_list(column: str, values: tuple[str, ...]) -> str:
    return f"{column} IN ({', '.join(repr(v) for v in values)})"


class ContentTranslation(Base):
    __tablename__ = "content_translations"
    __table_args__ = (
        # Declared here, not only in the migration, so the SQLite test schema
        # enforces them too.
        CheckConstraint(
            _in_list("content_type", TRANSLATION_CONTENT_TYPES),
            name="ck_content_translation_type",
        ),
        CheckConstraint(
            _in_list("field", TRANSLATION_FIELDS),
            name="ck_content_translation_field",
        ),
        # Its leading (content_type, content_id) columns also serve every
        # per-content lookup, so no separate index is needed for those.
        UniqueConstraint(
            "content_type", "content_id", "field", "target_lang", "source_hash",
            name="uq_content_translation",
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

    content_type: Mapped[str] = mapped_column(Text, nullable=False)
    content_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    field: Mapped[str] = mapped_column(Text, nullable=False)
    target_lang: Mapped[str] = mapped_column(Text, nullable=False)

    # sha256 of the normalised source text (translation_service.source_hash).
    source_hash: Mapped[str] = mapped_column(Text, nullable=False)

    # The language the provider saw, which can differ from the row's own
    # source_lang (that one is detected locally, and may be NULL).
    source_lang: Mapped[str | None] = mapped_column(Text, nullable=True)

    translated_text: Mapped[str] = mapped_column(Text, nullable=False)
    provider: Mapped[str] = mapped_column(Text, nullable=False)
    model: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        # Python-side default keeps SQLite (tests) aware and comparable.
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    def __repr__(self) -> str:
        return (
            f"<ContentTranslation {self.content_type}:{self.content_id} "
            f"{self.field}→{self.target_lang}>"
        )
