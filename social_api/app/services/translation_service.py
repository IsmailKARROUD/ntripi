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
from dataclasses import dataclass
from typing import TYPE_CHECKING, Iterable, Iterator

from sqlalchemy import and_, delete, not_, or_, select
from sqlalchemy.orm import Session

from app.models.annotation import Annotation
from app.models.content_translation import ContentTranslation
from app.models.itinerary import Itinerary
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.itinerary_rating import ItineraryRating
from app.models.stop import Stop
from app.models.transport_leg import TransportLeg
from app.services import language_detection, text_moderation_service, translation_validation
from app.services.moderation_policy import evaluate as evaluate_moderation
from app.services.text_moderation_providers import (
    ProviderUnavailableError,
    get_provider_chain as get_moderation_chain,
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


def run_chain(
    fields: dict[str, str],
    target_lang: str,
    settings: "Settings",
    chain: list[Translator] | None = None,
) -> ChainOutcome:
    """Translate `fields` (key → non-empty source text) into `target_lang`.

    Each engine gets only what the engines before it could not translate, in
    batches it can take. A field counts as translated once its output passes
    translation_validation and, when enabled, output moderation; anything else
    falls through to the next engine. Keys are the caller's own and never leave
    the server — the engines see texts only.
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
            try:
                result = translator.translate(batch, target_lang)
            except TranslatorUnavailableError as exc:
                reason = "quota" if isinstance(exc, TranslatorQuotaExceededError) else "error"
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
