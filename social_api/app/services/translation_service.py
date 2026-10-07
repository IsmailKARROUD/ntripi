"""
services/translation_service.py — translations of user-written text.

The registry of what is translatable, the source-language stamp every write
sets, and the rules that keep the translation cache in step with the text it
was made from.

A cached translation is keyed by a hash of its source text, so a stale one is
never served — it simply stops matching. Deleting it in the same transaction as
the edit (or the delete) is what keeps rewritten or removed text from living on
in a derived copy.
"""

from __future__ import annotations

import hashlib
import unicodedata
import uuid
from dataclasses import dataclass
from typing import Iterable

from sqlalchemy import and_, delete, not_, or_, select
from sqlalchemy.orm import Session

from app.models.annotation import Annotation
from app.models.content_translation import ContentTranslation
from app.models.itinerary import Itinerary
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.itinerary_rating import ItineraryRating
from app.models.stop import Stop
from app.models.transport_leg import TransportLeg
from app.services import language_detection


@dataclass(frozen=True)
class TranslatableType:
    content_type: str
    model: type
    # The fields a viewer may have translated, in display order. Detection
    # reads them together: more text, better guess.
    fields: tuple[str, ...]


# Every row of these tables belongs to exactly one itinerary — the premise of
# content_translations.itinerary_id. Stop names, addresses and leg lines are
# absent on purpose: they are place names, and nothing records whether a stop
# name was typed or came from the map.
REGISTRY: tuple[TranslatableType, ...] = (
    TranslatableType(
        "itinerary", Itinerary, ("title", "description", "recommended_period_note"),
    ),
    TranslatableType("itinerary_annotation", ItineraryAnnotation, ("content",)),
    TranslatableType("stop", Stop, ("notes",)),
    TranslatableType("stop_annotation", Annotation, ("content",)),
    TranslatableType("rating", ItineraryRating, ("note",)),
    TranslatableType("transport_leg", TransportLeg, ("notes",)),
)

_BY_MODEL = {spec.model: spec for spec in REGISTRY}


def normalize_source(text: str) -> str:
    """The form of a text that is hashed and sent for translation. Line endings
    and surrounding whitespace never change what it says, so they must not
    change its key either."""
    return unicodedata.normalize("NFC", text).replace("\r\n", "\n").strip()


def source_hash(text: str) -> str:
    return hashlib.sha256(normalize_source(text).encode("utf-8")).hexdigest()


def detect_source_lang(texts: Iterable[str | None]) -> str | None:
    """The language of one row's translatable fields, read as one text — a
    title alone is often too short to tell, its description rarely is."""
    return language_detection.detect(
        "\n\n".join(text for text in texts if text and text.strip())
    )


def sync_translations(db: Session, row, changed: Iterable[str] | None = None) -> None:
    """Re-detect `row.source_lang` and drop the translations its text outgrew.

    Call on every write of translatable text, before the commit, so both land
    in the edit's own transaction. `changed` is the set of submitted keys: when
    it names no translatable field the text is untouched and nothing runs.
    Unchanged text keeps its translations — only a field whose hash moved loses
    them.
    """
    spec = _BY_MODEL[type(row)]
    if changed is not None and not set(changed) & set(spec.fields):
        return

    present = {
        name: text
        for name in spec.fields
        if (text := getattr(row, name)) and text.strip()
    }
    row.source_lang = detect_source_lang(present.values())

    if row.id is None:
        return  # not flushed yet: a new row has no translations to drop

    still_current = [
        and_(
            ContentTranslation.field == name,
            ContentTranslation.source_hash == source_hash(text),
        )
        for name, text in present.items()
    ]
    stmt = delete(ContentTranslation).where(
        ContentTranslation.content_type == spec.content_type,
        ContentTranslation.content_id == row.id,
    )
    if still_current:
        stmt = stmt.where(not_(or_(*still_current)))
    db.execute(stmt.execution_options(synchronize_session=False))


def purge_orphans(db: Session, itinerary_id: uuid.UUID | None = None) -> int:
    """Delete translations whose content row no longer exists; return how many.

    Deleting a stop cascades its annotations and its segments' legs inside the
    database, where no application code sees which rows went — so the delete
    paths below the itinerary call this instead of naming what they deleted.
    Scoped to one itinerary it is a few indexed anti-joins; unscoped it is the
    safety net for anything a path missed. Deleting a trip or an account needs
    neither: the itinerary_id foreign key cascades.
    """
    purged = 0
    for spec in REGISTRY:
        content_exists = (
            select(spec.model.id)
            .where(spec.model.id == ContentTranslation.content_id)
            .exists()
        )
        stmt = delete(ContentTranslation).where(
            ContentTranslation.content_type == spec.content_type,
            ~content_exists,
        )
        if itinerary_id is not None:
            stmt = stmt.where(ContentTranslation.itinerary_id == itinerary_id)
        result = db.execute(stmt.execution_options(synchronize_session=False))
        purged += result.rowcount or 0
    return purged
