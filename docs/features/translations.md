# Translations

**Status:** in progress — groundwork only. Source-language detection and the
translation cache's lifecycle are built; **nothing translates yet, and nothing is
visible to users.**
**Tables:** `content_translations` · `source_lang` on six content tables
**Config:** `TRANSLATION_DETECT_LANGS`

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

## Known gaps / TODOs

- **Transport-leg notes are translatable on the server only** — no screen shows
  leg notes to a viewer today.
- **lingua reports Chinese without telling Simplified from Traditional** — both
  are stored as `zh`.
- **Rows that stay undetected are re-read by every backfill run.** Harmless
  (the run is bounded and changes nothing for them), but not free.

## Related

- [itineraries.md](itineraries.md) · [annotations.md](annotations.md) ·
  [ratings.md](ratings.md) · [tracks-and-stops.md](tracks-and-stops.md) ·
  [transit-segments.md](transit-segments.md) — the translatable fields
- [accounts-and-profiles.md](accounts-and-profiles.md) — account deletion, and
  the anonymised review
- [reference/data-model.md](../reference/data-model.md#content_translations)
- [decisions.md](../decisions.md) — why the cache cascades from the itinerary
