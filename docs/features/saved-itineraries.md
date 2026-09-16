# Saved itineraries

**Status:** shipped
**Tables:** `saved_itineraries`
**Config:** none

## Purpose

A bookmark. A user saves someone else's itinerary and finds it again on the Saved
tab. Deliberately minimal: presence of the row is the whole state.

## Rules

- **Composite PK `(itinerary_id, user_id)`** — the constraint *is* the "saved
  once" rule; there is no status column and no soft delete.
- **`POST /save` is idempotent, and the early return sits *above* the notify
  call** (`itineraries.py:1893`) — so re-saving never re-notifies the owner.
- **You cannot save your own itinerary** — 400 `cannot_save_own_itinerary`.
- **`DELETE /save` performs no existence or visibility check, by design**
  (`itineraries.py:1917`). You must be able to unsave something that has since
  become invisible to you. It answers 204 either way.
- **Rows are never deleted on a visibility change.** `GET /itineraries/saved`
  filters through `can_view_itinerary` **per row** at read time, so a trip that
  goes private simply stops appearing and comes back if access is restored.
- List order is `saved_at DESC, Itinerary.id DESC` — the id is the stable
  tie-breaker.
- Saving is `VIEWER_WRITE`: no edit lock, no `If-Match`.

## Data model

`saved_itineraries` — composite PK, both FKs CASCADE, plus `saved_at`.

`ix_saved_itineraries_user_id` was added in `a681984a1a04` because the composite
PK leads with `itinerary_id` and therefore cannot answer `WHERE user_id = me` —
which is the only query the Saved tab runs.

Full columns:
[reference/data-model.md](../reference/data-model.md#saved_itineraries).
Migration: `7bc2673b9ade`.

## API surface

| Method | Path | Auth | Response | Errors |
|---|---|---|---|---|
| POST | `/itineraries/{id}/save` | user | 204, idempotent | 404, 400 `cannot_save_own_itinerary`, 403 `itinerary_access_denied` |
| DELETE | `/itineraries/{id}/save` | user | 204 | none — no existence check |
| GET | `/itineraries/saved` | user | `list[ItinerarySummary]` | — |

## Flutter surface

- **`SavedItinerariesScreen`** — route `/saved`, its own shell branch (branch 4).
- **`savedItinerariesProvider`** — `AsyncNotifierProvider`, the list.
- **`isItinerarySavedProvider`** — `Provider.family` keyed by itinerary id,
  **derived** from the list rather than fetched, so the bookmark icon needs no
  per-itinerary request.
- The bookmark control is hidden for the owner and in edit mode.
- Saving warms the offline cache for the saved itinerary, so a bookmarked trip is
  readable offline.

## Known gaps / TODOs

- `cannot_save_own_itinerary` has no client-side localization
  (see [reference/error-codes.md](../reference/error-codes.md#unmapped-codes)),
  though the UI hides the control for owners so it should be unreachable.
- No dedicated test file; `test_saved_itineraries.py` exists and is **not**
  skipped.

## Related

- [itineraries.md](itineraries.md) · [visibility-and-access.md](visibility-and-access.md)
- [notifications.md](notifications.md) — `itinerary_saved` (mutable, switchable)
- [feed-and-search.md](feed-and-search.md) — where trips are usually found
- [reference/data-model.md](../reference/data-model.md)
