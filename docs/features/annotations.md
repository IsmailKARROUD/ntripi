# Annotations

**Status:** shipped
**Tables:** `annotations`, `itinerary_annotations`
**Config:** none

## Purpose

Free-text notes attached to a trip, in one of four kinds: **advice**, **caution**,
**avoid**, **info**. There are two independent systems with the same four kinds —
per-stop notes ("the queue is shorter at the side entrance") and trip-wide notes
("book two months ahead").

## Rules

- **Two tables, not one polymorphic table.** `annotations` keys on `stop_id`;
  `itinerary_annotations` keys on `itinerary_id`. Both CASCADE.
- **The four types are identical in both** and are enforced by a DB CHECK
  (`ck_annotation_type`, `ck_itinerary_annotation_type`) *and* the Pydantic
  `_NOTE_TYPE_PATTERN` regex. `transport_legs.note_type` reuses the same four.
- **The two Response classes stay separate on purpose.** A shared base would make
  base-class fields serialize first and reorder the JSON keys, which is part of
  the API contract (`schemas/itinerary.py:82`). The *request* schemas do share
  bases — `_AnnotationCreateBase` and `_AnnotationUpdateBase` — because request
  key order is not observable.
- **`_get_stop_annotation_or_404` joins through `Stop`** (`itineraries.py:272`).
  That join is the IDOR guard: it proves the annotation belongs to *this*
  itinerary, not merely that it exists.
- **Every annotation write bumps the itinerary's `updated_at`.**
  `_save_annotation` / `_delete_annotation` (`itineraries.py:295`) call
  `_touch_itinerary`, so the ETag moves and other clients' caches invalidate.
- An update requires **at least one field** — `_AnnotationUpdateBase` makes both
  optional but the router rejects an empty body.
- `content` is 1–2000 characters, required on create.
- Both systems require `If-Match` on every mutation, and creating one requires a
  verified email.

## Data model

| | `annotations` | `itinerary_annotations` |
|---|---|---|
| FK | `stop_id` → `stops.id` CASCADE | `itinerary_id` → `itineraries.id` CASCADE |
| Index | `ix_annotations_stop_id` | `ix_itinerary_annotations_itinerary_id` |
| `type` | VARCHAR(20), CHECK 4 values | same |
| `content` | TEXT NOT NULL | same |
| `updated_at` | added by `e7f8a9b0c1d2` | added by `e7f8a9b0c1d2` |

Stop-level annotations arrived first (initial itinerary schema); trip-wide ones in
`c0d1e2f3a4b5`. Full columns:
[reference/data-model.md](../reference/data-model.md#annotations-stop-level).

## API surface

Six endpoints, three per system. All mutations take `require_edit_access`
(edit permission + `X-Edit-Lock` + `If-Match`); the two POSTs additionally require
a verified email.

| Method | Path | Request | Response |
|---|---|---|---|
| POST | `/itineraries/{id}/annotations` | `ItineraryAnnotationCreate` | `ItineraryAnnotationResponse` 201 |
| PATCH | `/itineraries/{id}/annotations/{ann}` | `ItineraryAnnotationUpdate` | `ItineraryAnnotationResponse` |
| DELETE | `/itineraries/{id}/annotations/{ann}` | — | 204 |
| POST | `/itineraries/{id}/stops/{stop}/annotations` | `AnnotationCreate` | `AnnotationResponse` 201 |
| PATCH | `/itineraries/{id}/stops/{stop}/annotations/{ann}` | `AnnotationUpdate` | `AnnotationResponse` |
| DELETE | `/itineraries/{id}/stops/{stop}/annotations/{ann}` | — | 204 |

Errors: 404 `annotation_not_found` (both), 404 `stop_not_found` on the stop POST,
plus the guard's 403 / 428 / 409 / 412.

`{type, content}` on create; both optional on update.
Responses carry `{id, <parent>_id, type, content, created_at, updated_at}`.

Stop annotations also ride along inside `StopResponse.annotations`, and
trip-wide ones inside `ItineraryDetail.annotations` — which is how the client
normally reads them.

## Flutter surface

- **`AnnotationScreen`** (`features/itineraries/presentation/annotation_screen.dart:24`)
  serves **both** systems. It is **not a go_router route** — it is pushed through
  the free function `showAnnotationScreen()` (same file, line 381) via
  `Navigator.push`, from six call sites: `stop_detail_screen.dart:133`,
  `stop_form_screen.dart:811,846`, and `itinerary_detail_screen.dart:368,380,418,433`.
- Returns an `AnnotationFormResult` to its caller rather than writing directly.
- **Models** — `Annotation`, `AnnotationType`
  (`features/itineraries/domain/`), manual `fromJson`/`toJson`.
- Annotations are rendered from the detail payload, so no dedicated provider
  exists; mutations invalidate `itineraryDetailProvider`.

## Known gaps / TODOs

- **`test_annotations.py` is skipped** with `"rewriting after
  fractional-indexing refactor"` since 2026-05-07. Both systems have had no
  direct test coverage for four months.
- Neither table carries a `moderation_status`. Annotation text **rolls up to the
  parent itinerary** — hiding is itinerary-level, so a per-fragment status would
  have no read path. See [text-moderation.md](text-moderation.md).

## Related

- [tracks-and-stops.md](tracks-and-stops.md) — the parent of stop-level notes
- [itineraries.md](itineraries.md) — the parent of trip-wide notes
- [transit-segments.md](transit-segments.md) — `note_type` reuses the four types
- [collaborative-editing.md](collaborative-editing.md) — the write guard
- [etag-concurrency.md](etag-concurrency.md) — why every write touches `updated_at`
- [text-moderation.md](text-moderation.md) — both tables are scanned, and roll up
- [reference/data-model.md](../reference/data-model.md)
