# Tracks and stops (fractional indexing)

**Status:** shipped
**Tables:** `tracks`, `stops`
**Config:** none

## Purpose

A track is a vertical column of **parallel alternatives** at one point in a trip
("Hotel A or Hotel B on night 2"). A stop is one place inside a track. Both are
ordered by lexicographic string ranks rather than integer positions, so inserting
or moving one item writes exactly one row.

## Rules

### Ordering

- **`services/ordering.py` is the only place ranks are computed.** Public API:
  `key_between(a, b)` and `n_keys_between(a, b, n)`.
- Base-62 alphabet `0-9A-Za-z` (`ordering.py` `_DIGITS`). ASCII order equals
  `COLLATE "C"` order equals Python's default string comparison — that identity
  is what lets the server sort in SQL and the router sort in Python and get the
  same answer.
- `_INITIAL = "a0"` for an empty list — it leaves room above and below.
  `key_between(None, None) → "a0"`, `key_between("a0", None) → "b"`,
  `key_between("a0", "b") → "a1"`, `key_between("a0", "c") → "b"`,
  `key_between("a0", "a1") → "a01"`.
- **Appending past a maxed digit keeps going.** When `a`'s digit is already `z`,
  the key keeps it and steps above `a`'s *next* digit (`"z" → "z1"`,
  `"zV" → "zW"`). Until 2026-09-28 it returned a fixed `"zV"` whatever followed,
  so appends went `… z → zV → zV`: the 28th stop or track added at the end
  collided forever (`409 rank_collision` on every retry, a 500 on a move). Pinned
  by 500 tail appends, 500 head prepends and 2000 random inserts in
  `test_fractional_indexing_smoke.py`.
- `key_between` raises `ValueError` if `a >= b`. The router turns that into
  **412 `itinerary_stale`**, not a 422: out-of-order anchors mean the client's
  view of the list is stale.
- `MAX_RANK_LENGTH = 32`. Exceeding it triggers `_rebalance_track`
  (`itineraries.py:424`), which renumbers the column and recomputes once with
  `allow_rebalance=False`.
- **`_two_phase_renumber` (`itineraries.py:230`) is the only way to rewrite a
  full rank set.** It parks every row on `'!' + id` first — `!` is ASCII 33,
  below every character in the base-62 alphabet — flushes, then assigns the new
  keys. Without the two phases the UNIQUE constraints would fire mid-update.
- **`ranks` are never sent by the client.** The client sends order; the server
  computes keys.

### Track lifecycle

- **A track exists only while it holds ≥ 1 stop.** Creating a stop with
  `track_id: null` creates the track and the stop atomically
  (`itineraries.py:1332`). `_delete_track_if_empty` (`itineraries.py:404`) runs
  after every stop delete and every cross-track move.
- This is enforced in application code, **deliberately not a DB trigger**.

### Stops

- **Stop role is not stored.** There is no `type` column — it was dropped in
  `f1e2d3c4b5a6`, and `models/stop.py:18` says "Never add it back". The role is
  derived client-side in `Itinerary._parseTracks()`: 1 track → all `origin`;
  2+ tracks → first `origin`, last `arrival`, rest `waypoint`.
- **There is no `position` or `parallel_position` column either**, and neither
  may appear in any API payload.
- `stops.itinerary_id` is **denormalised** alongside `track_id`
  (`models/stop.py:62`) so the totals recalculation needs no join.
- `add_stop` retries up to **3 times** on `IntegrityError` from the rank UNIQUE,
  then answers 409 `rank_collision` (`itineraries.py:1324`). Text moderation runs
  **before** the retry loop so a collision never re-bills a provider call.
- **A new track with no anchor is appended after the last one**
  (`_resolve_track_rank`). `key_between(None, None)` is a fixed midpoint, so
  before 2026-09-26 an unanchored `track_id=null` create collided with the first
  track on any non-empty itinerary and every retry hit the same key. The app
  always sends `after_track_id` there, so only direct API callers saw it.
- `StopUpdate._validate_move_target` (`schemas/itinerary.py:203`) rejects
  `after_track_id`/`before_track_id` unless `track_id` is null — otherwise the
  intent ("move to that track" vs "make a new track there") is ambiguous.
- `map_url` is the security boundary. `validate_google_maps_url`
  (`schemas/itinerary.py:62`) allows http(s) only, any path on
  `maps.google.com` / `maps.app.goo.gl`, and only `/maps` paths on
  `google.com` / `www.google.com` / `goo.gl`.
- `is_free` is distinct from `cost = 0` — the totals calculation sums only
  non-`is_free` rows.

### Reorder

`POST /itineraries/{id}/reorder` validates everything before writing:

- each `stop_orders[track_id]` must be **exactly** that track's current stop set
  — no missing, no extra, no duplicates;
- `track_order`, if given, must be exactly the current track set;
- every track and every `segments_to_delete` id must belong to this itinerary;
- at least one of the three fields must be present.

Six distinct 422 messages come out of this, all as plain `HTTPException` with no
error code.

## Data model

`tracks` — `rank` TEXT with UNIQUE `uq_track_rank (itinerary_id, rank)`.
`stops` — `rank` TEXT with UNIQUE `uq_stop_rank (track_id, rank)`.
Full columns: [reference/data-model.md](../reference/data-model.md#tracks).

**`COLLATE "C"` and the `(itinerary_id, rank)` / `(track_id, rank)` indexes exist
only in migration `d5e6f7a8b9c0`, not in the ORM models** — so the test suite,
which builds from ORM metadata on SQLite, never exercises them. See
[Migration-only objects](../reference/data-model.md#migration-only-objects).

`place_type` has **no DB CHECK** — only the Pydantic `_PLACE_TYPE_PATTERN`
regex. The 11 values are:
`eatDrink · sleep · pray · learnSee · buy · playWatch · nature · transport ·
healBathe · entertainment · sight`. `travel` is the pre-rename spelling of
`transport` (`c78a28a2e02f`): the backend now rejects it, and only the client's
`PlaceType.fromString()` still maps it, for rows stored before the rename.

Migration `d5e6f7a8b9c0` is a **clean-slate** migration: it wipes `annotations`,
`transit_segments` and `stops` on upgrade.

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/{id}/stops` | verified email **+** `require_edit_access` | `StopCreate` | `StopResponse` 201 + ETag | 404 `track_not_found`, 422 (uncoded) bad anchors, 412 `itinerary_stale`, 409 `rank_collision` |
| PATCH | `/itineraries/{id}/stops/{stop_id}` | `require_edit_access` | `StopUpdate` | `StopResponse` + ETag | 404 `stop_not_found`, 422, 412 |
| DELETE | `/itineraries/{id}/stops/{stop_id}` | `require_edit_access` | — | 204 + ETag | 404 `stop_not_found` |
| POST | `/itineraries/{id}/reorder` | `require_edit_access` | `ReorderRequest` | `ItineraryDetail` + ETag | 422 (six uncoded messages) |

**There are no track endpoints.** Tracks are created and destroyed as a
side-effect of stop writes, and reordered through `reorder`.

`StopCreate` placement fields: `track_id?`, `after_stop_id?`, `before_stop_id?`,
`after_track_id?`, `before_track_id?`. Content fields: `place_name` (≤200),
`place_address` (≤400), `lat` (−90..90), `lng` (−180..180), `map_url` (≤500),
`place_type`, `duration_min` (≥0), `cost` (≥0), `is_free`, `notes` (≤2000).

`ReorderRequest` = `{stop_orders: {track_id: [stop_id…]}, track_order?: [...],
segments_to_delete: [...]}`.

`TrackResponse` = `{id, itinerary_id, rank, stops: [StopResponse]}`.
`StopResponse` carries `rank` and a nested `annotations` list.

`reorder` returns the freshly reloaded detail — `_etag_json_response` must be
passed that, not the stale itinerary.

## Flutter surface

- **Screens** — `StopFormScreen` (`/itineraries/:id/stops/new`,
  `/itineraries/:id/stops/:stopId/edit`), `StopDetailScreen`
  (`/itineraries/:id/stops/:stopId`), `MapPickerScreen` (`/map-picker`).
- **Reorder / move sheets** (`features/itineraries/presentation/widgets/`):
  `track_reorder_view.dart`, `reorder_parallels_sheet.dart` (labelled Phase 2a),
  `move_stop_to_track_sheet.dart` (Phase 2c).
- **Models** — `Stop`, `Track`, `PlaceType`, `StopType`
  (`features/itineraries/domain/`). `Stop.fromJson` always sets a placeholder
  `waypoint`; the real role is assigned after deserialisation by
  `Itinerary._parseTracks()`. **Always use `PlaceType.fromString()`** — it handles
  legacy values and returns null for unknowns.
- **The place type is what a stop looks like in the list and on the map.**
  `StopCard`'s number badge is tinted and ringed in `PlaceType.color(nt)` with
  the type's icon on its trailing-bottom corner (a `PositionedDirectional`, so it
  flips for Arabic). The detail screen's map marker takes the same color and
  icon. Two rules keep it legible: the digit stays `nt.bark`, never the place
  color, because Sight and Play & watch fall under 4.5:1 for 14 px text; and a
  glyph drawn on a place-color fill is `nt.surface`, which is white on the
  saturated light palette and black on the pastel dark one. The corner icon
  carries a `Semantics` label, so a screen reader announces the row as
  "3, Sleep, …". An untyped stop keeps the plain `nt.mist` badge, and its marker
  keeps the start/middle/end color (`_markerColors`). The reorder sheets number
  whole tracks, which can mix types, so they stay neutral. Regression test:
  `test/widgets/stop_card_place_type_test.dart`.
- **Any editing route claims the edit lock before pushing.** `_openStopForm` does
  the round trip first and abandons the push if the claim is refused — no form
  claims a lock for itself, so a route pushed without one looks editable and then
  428s on Save. The stop page (`StopDetailScreen`) shows its edit chrome to
  editors too, and editing from it enters the trip's edit mode — the claim is
  kept, and a trip someone else holds answers with a pop-up that offers the
  takeover when allowed. See [collaborative-editing.md](collaborative-editing.md).
- **A create that half-failed is finished, not repeated.** `StopFormScreen`
  remembers the stop its Save created (`_createdStop`) and drops each queued note
  as it lands. If a note then fails (a moderation 422, say), Save again updates
  that stop (placement keys stripped — on a PATCH `track_id` means "move") and
  posts only the notes left; it used to offer "Add anyway" and create a second
  stop.
- **A parallel group survives losing the stop on screen.** `ParallelStopGroup`'s
  State outlives rebuilds (a per-track `GlobalKey`), so deleting or moving out the
  parallel being viewed left its page index past the new end — a RangeError in
  build. `didUpdateWidget` clamps the index and rebuilds the page view with a
  controller already on the new page (`expandable_page_view` sizes an internal
  list by the old item count).
- **A parallel page is never wrapped in `IntrinsicHeight`.** `ExpandablePageView`
  already lays each page out unconstrained (an `OverflowBox`, 0 → ∞) and measures
  it, so a card takes its natural height without help. `StopCard`'s read-mode
  notes use a `LayoutBuilder` (the "view more" overflow check), which throws on
  an intrinsic query: from May until 2026-09-29 every parallel track with notes
  collapsed to 0 px in view mode and re-threw on each relayout, freezing the
  app. Regression test: `test/widgets/parallel_stop_group_layout_test.dart`.
- Inserting a track between two adjacent tracks joined by a segment shows a
  confirmation first, then deletes the segment(s) — see
  [transit-segments.md](transit-segments.md).

## Known gaps / TODOs

- **`COLLATE "C"`, `idx_tracks_itinerary` and `idx_stops_track` are untested** —
  they are migration-only, and the suite runs on SQLite from ORM metadata. A
  regression in the collation would not fail any test; it would silently reorder
  every itinerary in production.
- `test_fractional_indexing_smoke.py` is the designated home for new ordering
  tests. The six sibling files skipped by the commit that introduced fractional
  indexing (2026-05-07) run again since 2026-09-26.
- **"Phase 2b — whole-track reorder" is referenced but not built**
  (`move_stop_to_track_sheet.dart:20`). The sheet clears segments now
  specifically so a Phase 2b that restores track adjacency cannot resurrect a
  stale one.
- The reorder endpoint's six 422s carry no error code, so the client shows the
  server's English `detail`.

## Related

- [itineraries.md](itineraries.md) — the parent, and the totals these feed
- [transit-segments.md](transit-segments.md) — segments join two stops
- [annotations.md](annotations.md) — stop-level notes hang off `stops`
- [collaborative-editing.md](collaborative-editing.md) — the write guard and lock
- [etag-concurrency.md](etag-concurrency.md) — why bad anchors answer 412
- [text-moderation.md](text-moderation.md) — stop name, address and notes are scanned
- [translations.md](translations.md) — stop notes carry `source_lang` (never the place name); deleting a stop purges what cascaded
- [reference/data-model.md](../reference/data-model.md)

## OPEN QUESTIONS

- **`stops.place_type` has no DB CHECK** although `transport_legs.mode`,
  `annotations.type` and every moderation status do. The Pydantic regex is the
  only gate, so a direct SQL write could store anything; `PlaceType.fromString()`
  on the client would degrade it to null. Whether the asymmetry is deliberate is
  not recorded.
- **`_delete_track_if_empty` is app-level with a comment saying so, but no
  comment says why a DB trigger was rejected.** The choice is visible; the
  reasoning is not.
