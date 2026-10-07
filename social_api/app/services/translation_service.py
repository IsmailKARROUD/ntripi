"""
services/translation_service.py — translations of user-written text.

The registry of what is translatable, the source-language stamp every write
sets, the rules that keep the translation cache in step with the text it was
made from, and the engine chain that produces translations (run_chain).

A cached translation is keyed by a hash of its source text, so a stale one is
never served — it simply stops matching. Deleting it in the same transaction as
the edit (or the delete) is what keeps rewritten or removed text from living on
in a derived copy.
"""

from __future__ import annotations

import hashlib
import logging
import time
import unicodedata
import uuid
from collections import Counter
from dataclasses import dataclass, field as dataclass_field
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Iterable, Iterator

from sqlalchemy import and_, delete, not_, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.annotation import Annotation
from app.models.content_translation import ContentTranslation
from app.models.itinerary import Itinerary
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.itinerary_rating import ItineraryRating
from app.models.stop import Stop
from app.models.transit_segment import TransitSegment
from app.models.transport_leg import TransportLeg
from app.models.user import User
from app.database import SessionLocal, upsert_insert
from app.services import (
    language_detection, text_moderation_service, translation_usage, translation_validation,
)
from app.services.moderation_policy import evaluate as evaluate_moderation
from app.services.text_moderation_providers import (
    ProviderUnavailableError,
    get_provider_chain as get_moderation_chain,
)
from app.services.itinerary_access import (
    HIDDEN_STATUSES, can_view_itinerary, can_view_rating,
)
from app.services.translation_providers import (
    Translator,
    TranslatorQuotaExceededError,
    TranslatorUnavailableError,
    get_translator_chain,
)

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)


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
_BY_TYPE = {spec.content_type: spec for spec in REGISTRY}


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


# ---------------------------------------------------------------------------
# The engine chain
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ChainTranslation:
    text: str
    source_lang: str | None  # as the engine saw it
    provider: str
    model: str | None


@dataclass(frozen=True)
class ChainOutcome:
    translated: dict[str, ChainTranslation]
    # Fields no engine could translate → "<provider>:<reason>" of the last
    # attempt, for the logs and the tests. Never cached.
    failed: dict[str, str]


# Moderation outcomes that would refuse the text if a user had typed it.
_REJECTING_OUTCOMES = ("reject", "hide_escalate")


class Budget:
    """Each engine's daily character budget, kept in Postgres
    (translation_provider_usage). A reservation commits at once: characters
    sent are spent, whatever happens to the request afterwards."""

    def __init__(self, db: Session) -> None:
        self._db = db

    def reserve(self, translator: Translator, chars: int) -> bool:
        allowed = translation_usage.reserve_provider_chars(
            self._db, translator.name, chars,
            getattr(translator, "daily_char_budget", None),
            translation_usage.utc_now().date(),
        )
        self._db.commit()
        return allowed

    def exhausted(self, translator: Translator) -> None:
        translation_usage.mark_provider_exhausted(
            self._db, translator.name,
            getattr(translator, "daily_char_budget", None),
            translation_usage.utc_now().date(),
        )
        self._db.commit()


def run_chain(
    fields: dict[str, str],
    target_lang: str,
    settings: "Settings",
    chain: list[Translator] | None = None,
    *,
    budget: Budget | None = None,
) -> ChainOutcome:
    """Translate `fields` (key → non-empty source text) into `target_lang`.

    Each engine gets only what the engines before it could not translate, in
    batches it can take, while its daily budget lasts. A field counts as
    translated once its output passes translation_validation and, when enabled,
    output moderation; anything else falls through to the next engine. Keys are
    the caller's own and never leave the server — the engines see texts only.
    """
    if chain is None:
        chain = get_translator_chain(settings)
    pending = {key: normalize_source(text) for key, text in fields.items()}
    translated: dict[str, ChainTranslation] = {}
    failed = {key: "none:no_provider" for key in pending}

    for translator in chain:
        if not pending:
            break
        batches = list(_batches(
            pending, translator.max_batch_fields, translator.max_batch_chars,
        ))
        for batch in batches:
            started = time.monotonic()
            chars = sum(len(text) for text in batch.values())
            if budget is not None and not budget.reserve(translator, chars):
                _log_failure(translator, batch, started, "budget", "daily budget spent")
                failed.update({key: f"{translator.name}:budget" for key in batch})
                break
            try:
                result = translator.translate(batch, target_lang)
            except TranslatorUnavailableError as exc:
                quota = isinstance(exc, TranslatorQuotaExceededError)
                if quota and budget is not None:
                    budget.exhausted(translator)
                reason = "quota" if quota else "error"
                _log_failure(translator, batch, started, reason, exc)
                failed.update({key: f"{translator.name}:{reason}" for key in batch})
                break  # an outage or an empty quota will not clear mid-request
            except Exception as exc:  # a provider bug is still an outage
                logger.exception("translation provider %s raised", translator.name)
                failed.update({key: f"{translator.name}:error" for key in batch})
                break

            reasons: dict[str, str] = {}
            passed = {}
            for key, source in batch.items():
                output = result.outputs.get(key)
                why = (
                    "missing" if output is None
                    else translation_validation.failure(source, output.text)
                )
                if why:
                    reasons[key] = why
                else:
                    passed[key] = output
            for key, why in _moderation_refusals(
                {key: output.text for key, output in passed.items()}, settings,
            ).items():
                reasons[key] = why
                del passed[key]

            for key, output in passed.items():
                translated[key] = ChainTranslation(
                    text=output.text, source_lang=output.source_lang,
                    provider=result.provider, model=result.model,
                )
                del pending[key]
                failed.pop(key, None)
            failed.update({key: f"{translator.name}:{why}" for key, why in reasons.items()})
            _log_call(translator, batch, passed, reasons, started)

    return ChainOutcome(
        translated=translated,
        failed={key: failed[key] for key in pending},
    )


def _batches(
    fields: dict[str, str], max_fields: int, max_chars: int,
) -> Iterator[dict[str, str]]:
    batch: dict[str, str] = {}
    chars = 0
    for key, text in fields.items():
        if batch and (len(batch) >= max_fields or chars + len(text) > max_chars):
            yield batch
            batch, chars = {}, 0
        batch[key] = text
        chars += len(text)
    if batch:
        yield batch


def _moderation_refusals(texts: dict[str, str], settings: "Settings") -> dict[str, str]:
    """Translations the text-moderation policy would refuse, keyed → reason.

    A translation is machine output every later reader is served, so text an
    instruction hidden in the source talked a model into must not be cached.
    Fails closed: with moderation on and no classifier answering, nothing new
    is cached — the original stays on screen, which costs a reader little.
    """
    if (
        not texts
        or not settings.TRANSLATION_MODERATE_OUTPUT
        or not text_moderation_service.is_enabled(settings)
    ):
        return {}
    keys = list(texts)
    for provider in get_moderation_chain(settings):
        try:
            results = provider.score_many([texts[key] for key in keys])
        except ProviderUnavailableError:
            continue
        except Exception:
            logger.exception("moderation provider %s raised on translations", provider.name)
            continue
        return {
            key: "moderation"
            for key, result in zip(keys, results)
            if evaluate_moderation(result.scores).outcome in _REJECTING_OUTCOMES
        }
    return {key: "moderation_unavailable" for key in keys}


def _log_call(translator, batch, passed, reasons, started) -> None:
    # Sizes and outcomes only — never a text, a key or a content id.
    logger.info(
        "translation provider=%s model=%s fields=%d translated=%d chars_in=%d "
        "chars_out=%d latency_ms=%d failures=%s",
        translator.name, translator.model, len(batch), len(passed),
        sum(len(text) for text in batch.values()),
        sum(len(output.text) for output in passed.values()),
        int((time.monotonic() - started) * 1000),
        dict(Counter(reasons.values())),
    )


def _log_failure(translator, batch, started, reason, exc) -> None:
    logger.warning(
        "translation provider=%s model=%s fields=%d chars_in=%d latency_ms=%d "
        "unavailable=%s detail=%s",
        translator.name, translator.model, len(batch),
        sum(len(text) for text in batch.values()),
        int((time.monotonic() - started) * 1000), reason, exc,
    )


# ---------------------------------------------------------------------------
# Translating content for a reader
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ItemRequest:
    content_type: str
    content_id: uuid.UUID
    fields: tuple[str, ...]


@dataclass(frozen=True)
class FieldResult:
    # translated | same_language | empty | unavailable | rate_limited
    status: str
    text: str | None = None
    provider: str | None = None
    source_lang: str | None = None


@dataclass
class ItemResult:
    content_type: str
    content_id: uuid.UUID
    status: str  # ok | not_found
    fields: dict[str, FieldResult] = dataclass_field(default_factory=dict)


@dataclass(frozen=True)
class _Miss:
    item: ItemResult
    field_name: str
    itinerary_id: uuid.UUID
    source_hash: str
    text: str


def translate_items(
    db: Session,
    settings: "Settings",
    viewer_id: uuid.UUID,
    target_lang: str,
    items: list[ItemRequest],
    chain: list[Translator] | None = None,
) -> list[ItemResult]:
    """Translate the requested fields of each item into `target_lang`, for one
    reader.

    Access is the one ladder, checked per trip: content the reader cannot see —
    missing, forbidden, or under a takedown even for its author — answers
    `not_found`, all alike, so nothing is learnt by asking. Cache hits are
    answered from content_translations; misses go to the engine chain with the
    transaction already closed, so no pooled connection waits on a provider.
    Successes are cached; failures never are.
    """
    results = [
        ItemResult(item.content_type, item.content_id, "not_found") for item in items
    ]
    rows = _load_rows(db, items)
    trip_readable: dict[uuid.UUID, bool] = {}

    lookups: dict[str, _Miss] = {}
    for item, result in zip(items, results):
        loaded = rows.get((item.content_type, item.content_id))
        if loaded is None:
            continue
        row, itinerary_id = loaded
        if itinerary_id not in trip_readable:
            trip_readable[itinerary_id] = _trip_readable(db, itinerary_id, viewer_id)
        if not trip_readable[itinerary_id]:
            continue
        if item.content_type == "rating" and not _review_readable(db, row, viewer_id):
            continue

        result.status = "ok"
        for name in dict.fromkeys(item.fields):
            text = getattr(row, name)
            if not text or not text.strip():
                result.fields[name] = FieldResult("empty")
            elif row.source_lang == target_lang:
                result.fields[name] = FieldResult("same_language", source_lang=target_lang)
            else:
                lookups[f"{item.content_type}:{item.content_id}:{name}"] = _Miss(
                    item=result, field_name=name, itinerary_id=itinerary_id,
                    source_hash=source_hash(text), text=text,
                )

    misses = _answer_from_cache(db, target_lang, lookups)
    # Only what has to reach an engine counts against the reader: cache hits
    # are free. Over the limit, the misses are refused and the hits still served.
    if misses and not translation_usage.reserve_user_fields(
        db, viewer_id, len(misses), settings.TRANSLATION_USER_HOURLY_LIMIT,
        translation_usage.utc_now(),
    ):
        for miss in misses.values():
            miss.item.fields[miss.field_name] = FieldResult("rate_limited")
        misses = {}
    # Commits the reservation, and releases the connection before any engine is
    # called — nothing below needs one until the insert.
    db.commit()

    if misses:
        outcome = run_chain(
            {key: miss.text for key, miss in misses.items()}, target_lang, settings, chain,
            budget=Budget(db),
        )
        for key, translation in outcome.translated.items():
            misses[key].item.fields[misses[key].field_name] = _as_result(
                translation.text, translation.provider, translation.source_lang, target_lang,
            )
        for key in outcome.failed:
            misses[key].item.fields[misses[key].field_name] = FieldResult("unavailable")
        _store(db, target_lang, misses, outcome.translated)
    return results


def _select_with_itinerary(spec: TranslatableType):
    """`(row, itinerary_id)` for a content type — through the stop for a stop
    annotation, through the segment for a leg."""
    model = spec.model
    if model is Itinerary:
        return select(Itinerary, Itinerary.id)
    if model is Annotation:
        return select(Annotation, Stop.itinerary_id).join(Stop, Annotation.stop_id == Stop.id)
    if model is TransportLeg:
        return select(TransportLeg, TransitSegment.itinerary_id).join(
            TransitSegment, TransportLeg.segment_id == TransitSegment.id,
        )
    return select(model, model.itinerary_id)


def _load_rows(db: Session, items: list[ItemRequest]) -> dict:
    ids_by_type: dict[str, set[uuid.UUID]] = {}
    for item in items:
        ids_by_type.setdefault(item.content_type, set()).add(item.content_id)
    loaded = {}
    for content_type, ids in ids_by_type.items():
        spec = _BY_TYPE[content_type]
        query = _select_with_itinerary(spec).where(spec.model.id.in_(ids))
        for row, itinerary_id in db.execute(query).all():
            loaded[(content_type, row.id)] = (row, itinerary_id)
    return loaded


def _trip_readable(db: Session, itinerary_id: uuid.UUID, viewer_id: uuid.UUID) -> bool:
    """can_view_itinerary, minus takedowns. An owner may still see their hidden
    trip, but nothing legitimate needs it translated, and translating it would
    send taken-down text to a third party."""
    itinerary = db.get(Itinerary, itinerary_id)
    return (
        itinerary is not None
        and itinerary.hidden_at is None
        and itinerary.moderation_status not in HIDDEN_STATUSES
        and can_view_itinerary(itinerary, viewer_id, db)
    )


def _review_readable(db: Session, rating: ItineraryRating, viewer_id: uuid.UUID) -> bool:
    # Same rule as the trip: a review under takedown is not translated even for
    # its own author.
    return (
        rating.moderation_status not in HIDDEN_STATUSES
        and can_view_rating(rating, viewer_id, db)
    )


def _answer_from_cache(db: Session, target_lang: str, lookups: dict[str, _Miss]) -> dict[str, _Miss]:
    """Fill every field the cache can answer; return the ones it cannot."""
    if not lookups:
        return {}
    content_ids = {miss.item.content_id for miss in lookups.values()}
    cached = {
        (row.content_type, row.content_id, row.field, row.source_hash): row
        for row in db.execute(
            select(ContentTranslation).where(
                ContentTranslation.content_id.in_(content_ids),
                ContentTranslation.target_lang == target_lang,
            )
        ).scalars()
    }
    misses = {}
    for key, miss in lookups.items():
        hit = cached.get(
            (miss.item.content_type, miss.item.content_id, miss.field_name, miss.source_hash)
        )
        if hit is None:
            misses[key] = miss
        else:
            miss.item.fields[miss.field_name] = _as_result(
                hit.translated_text, hit.provider, hit.source_lang, target_lang,
            )
    return misses


def _as_result(text: str, provider: str, source_lang: str | None, target_lang: str) -> FieldResult:
    # The engine found the text already in the reader's language: there is
    # nothing to show instead of the original.
    if source_lang == target_lang:
        return FieldResult("same_language", provider=provider, source_lang=source_lang)
    return FieldResult("translated", text=text, provider=provider, source_lang=source_lang)


def _store(db: Session, target_lang: str, misses: dict[str, _Miss], translated: dict) -> None:
    """Cache the successes. Two readers missing the same text at once both
    insert; ON CONFLICT keeps the first. A trip deleted while its text was out
    for translation fails the foreign key — the reader still gets the answer,
    the cache just does not keep it."""
    if not translated:
        return
    now = datetime.now(timezone.utc)
    rows = [
        {
            "id": uuid.uuid4(),
            "itinerary_id": misses[key].itinerary_id,
            "content_type": misses[key].item.content_type,
            "content_id": misses[key].item.content_id,
            "field": misses[key].field_name,
            "target_lang": target_lang,
            "source_hash": misses[key].source_hash,
            "source_lang": translation.source_lang,
            "translated_text": translation.text,
            "provider": translation.provider,
            "model": translation.model,
            "created_at": now,
        }
        for key, translation in translated.items()
    ]
    try:
        db.execute(
            upsert_insert(db, ContentTranslation)
            .values(rows)
            .on_conflict_do_nothing(index_elements=[
                ContentTranslation.content_type, ContentTranslation.content_id,
                ContentTranslation.field, ContentTranslation.target_lang,
                ContentTranslation.source_hash,
            ])
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        logger.warning("translation cache insert skipped: content deleted meanwhile")


# ---------------------------------------------------------------------------
# Public trip titles, translated ahead of the reader
# ---------------------------------------------------------------------------

# Swappable so tests can hand the background task a session bound to their
# SQLite fixture (the push_service precedent).
_session_factory = SessionLocal


def pretranslate_title(itinerary_id: uuid.UUID, settings: "Settings") -> None:
    """Translate a public trip's title into TRANSLATION_PRETRANSLATE_LANGS.

    Runs as a FastAPI background task after the response is sent, so it opens
    its own session — the request's is gone by then. It re-reads the trip, so a
    title changed twice in a row is only ever translated as it now reads, and
    it skips any language already cached for the current text. The engines'
    daily budgets apply; no reader's quota does — nobody asked. Never raises:
    a reader who later taps "See translation" is the fallback.
    """
    db = _session_factory()
    try:
        itinerary = db.get(Itinerary, itinerary_id)
        if itinerary is None or not _pretranslatable(db, itinerary):
            return
        title = itinerary.title
        title_hash = source_hash(title)
        cached = set(db.execute(
            select(ContentTranslation.target_lang).where(
                ContentTranslation.content_type == "itinerary",
                ContentTranslation.content_id == itinerary.id,
                ContentTranslation.field == "title",
                ContentTranslation.source_hash == title_hash,
            )
        ).scalars())
        targets = [
            lang for lang in settings.translation_pretranslate_langs
            if lang != itinerary.source_lang and lang not in cached
        ]
        trip = ItemResult("itinerary", itinerary.id, "ok")
        miss = _Miss(item=trip, field_name="title", itinerary_id=itinerary.id,
                     source_hash=title_hash, text=title)
        db.commit()  # release the connection between engine calls

        for lang in targets:
            outcome = run_chain({"title": title}, lang, settings, budget=Budget(db))
            _store(db, lang, {"title": miss}, outcome.translated)
    except Exception:
        logger.exception("title pre-translation failed")
    finally:
        db.close()


def _pretranslatable(db: Session, itinerary: Itinerary) -> bool:
    """Only titles a stranger can read: public, live, not taken down, and an
    owner who is not banned."""
    if (
        itinerary.visibility != "public"
        or itinerary.deleted_at is not None
        or itinerary.hidden_at is not None
        or itinerary.moderation_status in HIDDEN_STATUSES
    ):
        return False
    owner = db.get(User, itinerary.user_id)
    return owner is not None and owner.is_active


def title_translations_for(
    db: Session, itineraries: Iterable[Itinerary], target_lang: str,
) -> dict[uuid.UUID, str]:
    """Cached title translations for a page of trips, one query. A trip whose
    title is already in `target_lang`, or whose cached translation was made
    from an older title, gets none."""
    hashes = {
        itinerary.id: source_hash(itinerary.title)
        for itinerary in itineraries
        if itinerary.source_lang != target_lang
    }
    if not hashes:
        return {}
    rows = db.execute(
        select(
            ContentTranslation.content_id, ContentTranslation.source_hash,
            ContentTranslation.source_lang, ContentTranslation.translated_text,
        ).where(
            ContentTranslation.content_type == "itinerary",
            ContentTranslation.field == "title",
            ContentTranslation.target_lang == target_lang,
            ContentTranslation.content_id.in_(hashes),
        )
    ).all()
    return {
        row.content_id: row.translated_text
        for row in rows
        if row.source_hash == hashes[row.content_id] and row.source_lang != target_lang
    }


# ---------------------------------------------------------------------------
# Housekeeping, from the sweep or by hand
# ---------------------------------------------------------------------------

def purge_for_sweep(db: Session) -> int:
    """Everything the cache no longer needs: translations whose content is gone
    (the safety net behind the per-path purge_orphans), translations of trips a
    moderator removed (restoring one just means translating again), and usage
    counters no limit can still read. The caller commits."""
    removed = purge_orphans(db)
    removed += db.execute(
        delete(ContentTranslation)
        .where(ContentTranslation.itinerary_id.in_(
            select(Itinerary.id).where(Itinerary.deleted_at.isnot(None))
        ))
        .execution_options(synchronize_session=False)
    ).rowcount or 0
    removed += translation_usage.purge(db, translation_usage.utc_now())
    return removed
