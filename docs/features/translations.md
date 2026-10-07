# Translations

**Status:** in progress. Source-language detection, the translation cache's
lifecycle and the engine chain are built; **no endpoint calls the engines yet,
and nothing is visible to users.**
**Tables:** `content_translations` · `source_lang` on six content tables
**Config:** `TRANSLATION_DETECT_LANGS`, `TRANSLATION_PROVIDERS` and the other
`TRANSLATION_*` / `AZURE_TRANSLATOR_*` settings below

## Purpose

Letting a reader see trips, notes and reviews in their own language. What exists
today is what every later piece depends on: each piece of translatable text
knows which language it is written in, and a cache table whose rows can never
outlive, or drift from, the text they were made from.

## Rules

### What is translatable

`translation_service.REGISTRY` is the single list:

| Content type | Table | Fields |
|---|---|---|
| `itinerary` | `itineraries` | `title`, `description`, `recommended_period_note` |
| `itinerary_annotation` | `itinerary_annotations` | `content` |
| `stop` | `stops` | `notes` |
| `stop_annotation` | `annotations` | `content` |
| `rating` | `itinerary_ratings` | `note` |
| `transport_leg` | `transport_legs` | `notes` |

- **Place names are not translatable** — `stops.place_name`, `place_address`,
  and a leg's `line` and `direction`. Nothing records whether a stop name was
  typed or filled in from OpenStreetMap or a Google Maps link, and either way
  it names a place.
- **Every row of these tables belongs to exactly one itinerary** — stop
  annotations through `stops`, legs through `transit_segments`. That is the
  premise of `content_translations.itinerary_id`.

### Source language

- **Detected at save time**, locally, by `lingua-language-detector`
  (`services/language_detection.py`) — no request, nothing leaves the server.
  High-accuracy mode, because trip titles are short.
- **Stored as `source_lang`**, ISO 639-1, on the row. An itinerary's language is
  read from title + description + period note together; a stop's from its notes
  only, so a French place name cannot make English notes read as French.
- **`NULL` means "not detected confidently"** — the best language must beat the
  runner-up by a margin (`_MIN_RELATIVE_DISTANCE = 0.1`), and text with fewer
  than three letters, or only URLs, mentions and emoji, is never labelled.
  Measured on short trip titles in eight languages: about one confident answer
  in forty was wrong at 0.1, against one in ten at 0.0. An undetected text is
  harmless; a wrong one can hide the translate button from a reader who needs
  it.
- **Detection never raises.** A write must not fail because detection did.

### The cache follows its source text

- A row is keyed by **`(content_type, content_id, field, target_lang,
  source_hash)`**. The hash is sha256 of the NFC-normalised text with `\r\n`
  folded to `\n` and the ends stripped (`translation_service.source_hash`). The
  source text itself is never stored.
- **Every write of translatable text calls `sync_translations`** before the
  commit: it re-detects `source_lang` and deletes the row's translations whose
  hash no longer matches its current text — in the edit's own transaction. Ten
  write paths in `routers/itineraries.py`: `create_itinerary`,
  `update_itinerary`, `add_stop`, `update_stop`, `_save_annotation` (both
  annotation tables, create and update), `upsert_rating`, `create_segment`,
  `update_segment`, `add_leg`, `update_leg`. A body that names no translatable
  field skips it.
- **Deleting a trip or an account needs nothing**: `itinerary_id` is a real FK
  with `ON DELETE CASCADE`.
- **Every delete below the itinerary calls `purge_orphans(db, itinerary_id)`**
  after its flush: `_delete_annotation`, `delete_stop`, `delete_my_rating`,
  `update_segment` (it replaces every leg), `delete_segment`, `delete_leg`, and
  `reorder_itinerary` when it deletes segments. It deletes the trip's
  translations whose content row is gone, rather than naming what was deleted —
  a stop's annotations and its segments' legs are removed by the database, out
  of the application's sight.
- **A review outlives its author anonymised, and so do its translations.**
  Account deletion sets `itinerary_ratings.user_id` to NULL; the review and its
  translation stay.
- **No user reference** anywhere in `content_translations`.

### The engines

- **`translation_service.run_chain(fields, target_lang, settings)`** translates
  a batch: each engine in `TRANSLATION_PROVIDERS` order gets only the fields the
  engines before it could not translate, split into batches it can take. A
  field nobody translated is reported back, never invented.
- **Two engines** (`services/translation_providers.py`), behind one
  `Translator` protocol — a new provider is a class plus an entry in
  `_FACTORIES`:

  | Name | What | Notes |
  |---|---|---|
  | `openai` | Responses API, `TRANSLATION_MODEL` (default `gpt-6-luna`) | strict `json_schema` built from the batch's keys; `store: false`; `reasoning.effort` from `TRANSLATION_REASONING_EFFORT` (empty omits it); a 429 `insufficient_quota` counts as quota exhausted |
  | `azure` | Azure AI Translator, REST v3 | a bare `[{"Text": …}]` array, no `from` so Azure reports the source per text; `zh` is sent as `zh-Hans`; a 403 means the free tier's characters are spent |

- **What leaves the server** is the texts, the target language and what the
  engine needs to process them — never a user id, an email, a content id or a
  field name. OpenAI receives the texts under opaque keys (`t0`, `t1`, …) and
  is told not to store the response.
- **Every translation is checked before it counts**
  (`services/translation_validation.py`): not empty; every URL and @mention
  kept verbatim; the same emoji and pictographic symbols; the same number of
  non-empty lines; and a length ratio inside 0.3–3.5 (0.12–7 when either side
  is Chinese, Japanese or Korean; skipped under 12 characters). A failure sends
  that field — only that field — to the next engine.
- **Output moderation**, when text moderation is on and
  `TRANSLATION_MODERATE_OUTPUT` is true: the batch's translations are scored in
  one call (`score_many`) and anything the policy would `reject` or
  `hide_escalate` fails. A translation is machine output served to every later
  reader, so an instruction hidden in the source must not be able to talk a
  model into caching something nobody typed. **It fails closed** — with no
  classifier answering, nothing new is translated and the original stays on
  screen. No decision rows are written: this is not user content.
- **An engine that fails a batch is not retried for the rest of the request**
  — an outage or an empty quota does not clear in a second.
- **Logs carry sizes and outcomes only**: provider, model, field count,
  characters in and out, latency, and failure reasons by count. Never a text,
  a key or a content id.

### API contract

`source_lang` is **appended last** to `ItineraryDetail` (after `can_edit`),
`StopResponse`, `AnnotationResponse`, `ItineraryAnnotationResponse`,
`TransportLegResponse` and `RatingWithUser`. `ItinerarySummary` is unchanged —
a new key there would reorder `/me`, `/saved` and `/feed`.

## Data model

`content_translations`, plus a nullable `source_lang` TEXT column on
`itineraries`, `itinerary_annotations`, `stops`, `annotations`,
`itinerary_ratings` and `transport_legs`. Full columns:
[reference/data-model.md](../reference/data-model.md#content_translations).
Migration: `f05c373d1b6c`.

## API surface

No endpoints yet. `source_lang` rides in the six responses listed above.

## Flutter surface

None yet.

## Operations

- **Backfill**, once per environment after the migration:
  `python scripts/backfill_source_lang.py --dry-run`, then without
  `--dry-run`, from `social_api/`. It walks each table in id order, reads only
  rows whose `source_lang` is NULL, and writes with a Core `UPDATE` that sets
  `updated_at` to itself, so neither the itinerary ETag nor a review's date
  moves. Safe to re-run.
- **Memory**: detection loads lingua's models lazily, per candidate language.
  With all 75 languages enabled, the process grew from about 10 MB to about
  76 MB on macOS after detecting a 14-language sample. `TRANSLATION_DETECT_LANGS`
  narrows the list if memory becomes tight.

## Config

| Var | Default | Notes |
|---|---|---|
| `TRANSLATION_DETECT_LANGS` | `all` | `all`, or comma-separated ISO 639-1 codes; a malformed value **raises at startup**. A shorter list loads fewer models, but text in another language is then forced onto its nearest neighbour in the list |
| `TRANSLATION_PROVIDERS` | empty | engines in the order to try them: `openai`, `azure`. Empty = translation off. An unknown or repeated name, or a provider without its key, **raises at startup** |
| `TRANSLATION_MODEL` | `gpt-6-luna` | reuses `OPENAI_API_KEY` |
| `TRANSLATION_REASONING_EFFORT` | `none` | empty omits the parameter; the lowest value differs per model (`minimal` for the gpt-5 family) |
| `TRANSLATION_TIMEOUT_SECONDS` | `10.0` | per engine call; must be positive |
| `AZURE_TRANSLATOR_KEY` / `_REGION` / `_ENDPOINT` | — / — / `https://api.cognitive.microsofttranslator.com` | the region is required for a regional or multi-service resource |
| `TRANSLATION_SUPPORTED_LANGS` | `en,fr,es,de,ar,zh` | target languages; each must be in `constants/translation_languages.py`, or startup **raises** |
| `TRANSLATION_MODERATE_OUTPUT` | `True` | only acts while `TEXT_MODERATION_PROVIDER` is not `disabled` |

## Known gaps / TODOs

- **Transport-leg notes are translatable on the server only** — no screen shows
  leg notes to a viewer today.
- **lingua reports Chinese without telling Simplified from Traditional** — both
  are stored as `zh`.
- **Azure's quota is read off HTTP 403.** Microsoft documents a 403 as
  "often" meaning the free characters are spent; a 403 for another reason (a
  resource misconfigured in the portal) reads the same way, and the field falls
  through to `unavailable` like any other failure.
- **Rows that stay undetected are re-read by every backfill run.** Harmless
  (the run is bounded and changes nothing for them), but not free.

## Related

- [itineraries.md](itineraries.md) · [annotations.md](annotations.md) ·
  [ratings.md](ratings.md) · [tracks-and-stops.md](tracks-and-stops.md) ·
  [transit-segments.md](transit-segments.md) — the translatable fields
- [accounts-and-profiles.md](accounts-and-profiles.md) — account deletion, and
  the anonymised review
- [text-moderation.md](text-moderation.md) — `score_many` vets every
  translation before it is cached
- [reference/data-model.md](../reference/data-model.md#content_translations)
- [decisions.md](../decisions.md) — why the cache cascades from the itinerary
