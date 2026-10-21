# Itineraries

**Status:** shipped
**Tables:** `itineraries`
**Config:** none (see [feed-and-search.md](feed-and-search.md) for `FEED_TOP_MIN_RATINGS`)

## Purpose

The itinerary is the unit of content: a titled trip with a cover image, a
currency, denormalised cost/duration totals, a visibility level, and an optional
"best time to visit" recommendation. Everything else — tracks, stops, segments,
annotations, ratings, saves, editors — hangs off it.

## Rules

- **The owner is `itineraries.user_id`**, FK CASCADE. Deleting an account deletes
  their itineraries outright.
- **`updated_at` IS the concurrency ETag.** Every content mutation bumps it via
  `_touch_itinerary`; anything that writes an itinerary from outside the owner's
  own request must go through `admin_service.set_preserving_etag` instead, or it
  412s the author's open editor over a change they cannot see. See
  [etag-concurrency.md](etag-concurrency.md).
- **Two soft-state columns, different meanings:** `deleted_at` hides the row from
  *everyone* including the owner; `hidden_at` hides it from everyone *except* the
  owner. Both are set only by the admin paths.
- **Denormalised totals.** `total_duration_min`, `total_cost`, `rating_avg`,
  `rating_count` and the response-only `stops_count` are maintained alongside
  their sources. `rating_avg`/`rating_count` are recomputed by SQL `AVG()` in
  `recalculate_rating()` — never in Python. `stops_count` is not a column at all
  but a Python property on the ORM model (`models/itinerary.py:195`); the three
  list endpoints eager-load `tracks → stops` specifically to keep it free of an
  N+1 (`itineraries.py:710,756,789`).
- **`currency` is a fixed-length 3-char field** (`min_length=3, max_length=3`),
  default `EUR`. No currency table, no validation against ISO-4217.
- **`visibility` is owner-only to change.** `require_edit_access` admits editors,
  but `update_itinerary`'s body rejects the *presence* of the key for a non-owner
  — so `visibility: null` 403s exactly as a real value does. The cover image is
  owner-only for the same reason. See
  [collaborative-editing.md](collaborative-editing.md).
- **Creating requires a verified email** (`require_verified_email`), which today
  means having signed in with Google. Reading and editing do not.
- **The itinerary form saves in one request** (since 2026-10-21): its fields and
  its cover change travel together, so one guard checks them together. The
  Edit itinerary form uses `PATCH /itineraries/{id}/form` for every save,
  editors included; the New itinerary form uses `POST /itineraries/form` when a
  cover was picked and `POST /itineraries/` otherwise. Until then the form sent
  the cover first (`POST`/`DELETE /itineraries/{id}/image`) and the fields after
  it with an `If-Match` read before the cover write moved `updated_at` — a 412 on
  every save that set a first cover, removed one, or got a flagging or failed
  scan, with the cover saved and the fields not (production logs, 2026-10-20).
  See [decisions.md](../decisions.md).
- **On the edit form route, nothing touches the row until both checks pass.**
  After the guard and the field validation, the text is scanned, then the cover
  is processed, scanned and stored, and only then are the verdicts, the cover URL
  and the fields applied, followed by `sync_translations` and one commit. Either
  refusal commits the session for its own audit row, which is why the itinerary
  must still be clean at that point. A removed cover's object is deleted after
  the commit, best-effort, so a failed save never takes the visible cover down.
- **The cover parts are the owner's.** An `image` or `remove_cover` from an
  editor is a 403 `itinerary_not_owner` for the whole request, with nothing
  saved; `visibility` keeps the PATCH's rule; an image needs a verified email,
  as `POST /image` does.
- **A create with a cover is all or nothing.** The id is assigned before the
  cover is stored under `itineraries/{id}.jpg`; text and image are both checked
  before the row is written, so a refused text or cover creates nothing, and a
  commit that fails after the object was stored deletes it best-effort. The
  image's audit row is linked to the new trip after the flush
  (`moderation_service.attach_itinerary`) — see
  [image-moderation.md](image-moderation.md).
- **JSON key order is the API contract.** `ItineraryDetail` declares `hidden`,
  the recommended-period fields and `can_edit` *inline and last* rather than by
  inheriting a mixin, because base-class fields serialize first and a mixin would
  reorder the whole response (`schemas/itinerary.py:600`–`627`). The same reason
  keeps `can_edit` off `ItinerarySummary`.
- **Lock state is deliberately absent from `ItineraryDetail`** — it changes on
  every heartbeat while this response's ETag does not, so it has its own endpoint.

## Data model

`itineraries` — see
[reference/data-model.md](../reference/data-model.md#itineraries) for the full
column list. Field limits enforced in `schemas/itinerary.py`:

| Field | Limit |
|---|---|
| `title` | 1–200 chars, required |
| `description` | ≤ 4000 (`_MAX_DESCRIPTION`) |
| `currency` | exactly 3 chars |
| `recommended_period_note` | ≤ 200 (`_MAX_PERIOD_NOTE`) |
| recommended period windows | ≤ 6 (`_MAX_PERIOD_WINDOWS`) |

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/` | verified email | `ItineraryCreate` | `ItinerarySummary` 201 | 422 `text_moderation_rejected` |
| POST | `/itineraries/form` | verified email | multipart: `fields` (`ItineraryCreate` as JSON) + `image` (required) | `ItinerarySummary` 201 | 422 (shape), 400 (unprocessable image), 422 `text_moderation_rejected` / `image_moderation_rejected` |
| GET | `/itineraries/me` | user | — | `list[ItinerarySummary]` | — |
| GET | `/itineraries/{id}` | user | — | `ItineraryDetail` + `ETag` | 404, 403 `itinerary_access_denied` |
| PATCH | `/itineraries/{id}` | `require_edit_access` | `ItineraryUpdate` | `ItinerarySummary` | 403 `itinerary_not_owner` (incl. `visibility` from an editor), 428/412, 409 |
| PATCH | `/itineraries/{id}/form` | `require_edit_access` | multipart: `fields` (`ItineraryUpdate` as JSON), `image?`, `remove_cover?` | `ItinerarySummary` + `ETag` | as PATCH, plus 403 `itinerary_not_owner` for a cover part from an editor, 403 `email_unverified` for an image, 422 (shape; both cover parts together), 400, 422 `image_moderation_rejected` |
| DELETE | `/itineraries/{id}` | **owner only** | — | 204 | 403, 428/412 |

`ItineraryCreate` = `{title, description?, currency='EUR', visibility='only_me'}`
plus the recommended-period fields.
`ItineraryUpdate` is the same, all optional.

**The form routes** are multipart because they carry a file. `fields` is one
text part holding the same JSON the JSON route takes, validated with the same
schema; a bad field answers FastAPI's own 422 body, located under the part
(`loc: ["body", "fields", "title"]` where the JSON route says
`["body", "title"]`). `remove_cover=true` takes the cover off; sending it with
an `image` is a 422 at `["body", "remove_cover"]`. Both routes are sync `def` —
FastAPI parses the multipart body before calling them — and reach the async
image pipeline through `anyio.from_thread.run`; see
[image-pipeline.md](image-pipeline.md#sync-and-async-upload-endpoints). The
edit route's answer carries the new concurrency `ETag`, and the client adopts
the summary in place instead of reloading. The JSON PATCH is unchanged: the
description editor, the recommended-period picker and the visibility screen use
it and never send an image.

`ItinerarySummary` = `{id, user_id, title, cover_image_url,
total_duration_min, total_cost, currency, visibility, created_at, updated_at,
rating_avg, rating_count, stops_count}`.

`ItineraryDetail` = that **plus, in this order** `description`, `tracks`,
`segments`, `annotations`, `hidden`, `recommended_periods`,
`recommended_weekdays`, `recommended_period_note`, `can_edit`.

`ItineraryFeedItem` = `ItinerarySummary` + `owner: RaterInfo`.

`GET /users/{user_id}/itineraries` lists another user's itineraries and is
registered from the same router under the `/users` prefix.

## Flutter surface

- **Screens** — `ItineraryListScreen` (`/itineraries`, shell branch 3),
  `ItineraryDetailScreen` (`/itineraries/:id`), `ItineraryFormScreen`
  (`/itineraries/new` and `/itineraries/:id/edit`), `RecommendedPeriodScreen`
  (pushed imperatively from the form and the detail screen, not routed).
- **Providers** (`features/itineraries/providers/itinerary_providers.dart`):
  | Provider | Type | Holds |
  |---|---|---|
  | `myItinerariesProvider` | `AsyncNotifierProvider` | the owner's list |
  | `itineraryDetailProvider` | `AsyncNotifierProvider.family` | one detail, keyed by id |
  | `itineraryScopeProvider` | `NotifierProvider` | Mine / Shared segment selection |
  | `userItinerariesProvider` | `AsyncNotifierProvider.family` | another user's list |
- **Repository** — `itineraryRepositoryProvider` → `ItineraryRepository`
  (`features/itineraries/data/itinerary_repository.dart`), which also converts the
  guard's rejections into the typed exceptions `ItineraryStaleException`,
  `EditLockLostException`, `ItineraryLockedException`,
  `EditLockRequiredException`. `saveItineraryForm` and `createItineraryWithCover`
  send the form routes; the client no longer calls the `/image` pair.
- **The form's save** — the edit branch calls
  `ItineraryDetailNotifier.saveForm(data, coverBytes:, removeCover:)`, which runs
  through `_write` (the only reader of the claim token) and adopts the answer
  the way `updateHeader` does (`_adoptHeader`: cover URL, `updatedAt`, so the
  ETag). After a cover change the form evicts the cached image under both the
  URL from before the save and the one after. The create branch calls
  `MyItinerariesNotifier.addItinerary(data, coverBytes:)`, which picks the
  multipart route when a cover was picked. A refusal of any kind — 412, a lost
  claim, a 422 on the text or the image — leaves the form open with every field
  and the picked image intact; on create that now includes a refused cover,
  which used to create the trip without it.
- **Model** — `Itinerary` (`features/itineraries/domain/itinerary.dart`), manual
  `fromJson`/`toJson`. `_parseTracks()` is where stop roles are derived.

## Known gaps / TODOs

- `ItineraryFormScreen` in edit mode opens on `mayEdit` and hides each owner-only
  control individually rather than gating the whole screen — a deliberate reversal
  of `1d3cf4a` on the same day (see [decisions.md](../decisions.md)).
- No test file covers itinerary CRUD directly; `test_feed_smoke.py` and
  `test_fractional_indexing_smoke.py` exercise it incidentally. The form routes
  have their own, `test_itinerary_form.py`.
- **The cover object is written before the commit, under its stable key.** On
  the edit form route a commit that fails after `process_and_store` leaves the
  new image at `itineraries/{id}.jpg` — visible at the old URL, or reachable
  with no row pointing at it for a first cover. Unguessable per-upload keys
  ([backlog.md](../backlog.md), share teaser step 2) would let the old object be
  deleted only after the commit.
- **A failed delete after a removal is not retried.** The row is committed
  without the cover and the object stays reachable at its key; the failure is
  logged at ERROR and nothing comes back for it.
- **A refused cover can leave a text verdict behind.** The image reject path
  commits the session, text decision included, so a `review` verdict on text
  the same request then did not save sits in the moderator queue. A
  `hide_escalate` verdict is escalated against the author instead
  ([text-moderation.md](text-moderation.md)).

## Related

- [visibility-and-access.md](visibility-and-access.md) — who may see it
- [tracks-and-stops.md](tracks-and-stops.md) · [transit-segments.md](transit-segments.md) · [annotations.md](annotations.md) — child content
- [ratings.md](ratings.md) · [saved-itineraries.md](saved-itineraries.md)
- [collaborative-editing.md](collaborative-editing.md) — the write guard
- [etag-concurrency.md](etag-concurrency.md) — `updated_at` as the ETag
- [image-pipeline.md](image-pipeline.md) — the cover image
- [text-moderation.md](text-moderation.md) — title and description are scanned
- [feed-and-search.md](feed-and-search.md) · [sharing.md](sharing.md)
- [translations.md](translations.md) — title, description and period note carry `source_lang`; their translations cascade with the trip
- [reference/data-model.md](../reference/data-model.md)

## OPEN QUESTIONS

- **`currency` is validated only for length.** Any three characters are accepted,
  so `"XXX"` or `"abc"` persists. Whether a whitelist was considered and rejected
  (the client offers a fixed picker via `core/services/currency.dart`) is not
  recorded.
- **`Itinerary.stops_count`'s fallback branch may be unreachable.** The property
  (`models/itinerary.py:195`) reads
  `sum(len(t.stops) for t in self.tracks) if self.tracks else len(self.stops)`.
  Since a stop cannot exist without a track (`stops.track_id` is NOT NULL), the
  `len(self.stops)` branch can only fire when `tracks` is empty — in which case
  `stops` is empty too, and both return 0. Whether the fallback guards a case
  that no longer exists or one that is not obvious is not recorded.
