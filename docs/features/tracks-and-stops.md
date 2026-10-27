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
- at least one of the four fields must be present.

Six distinct 422 messages come out of this, all as plain `HTTPException` with no
error code.

### Layout (arrange mode's save)

`layout` is the whole trip as it should stand — tracks in order, each with its
stops in order — and it is how the app saves arrange mode
([decisions.md](../decisions.md), 2026-10-27). Stops may change track; a null
`track_id` is a track to create; an existing track left out is deleted, since it
holds no stop any more.

- **Validated whole before any write** (`_validate_layout`): every stop of the
  itinerary exactly once (no missing, no extra, no duplicate), and every
  non-null `track_id` this itinerary's and listed once. Four more uncoded 422s;
  a schema 422 for an empty `stop_ids`, and for `layout` sent together with
  `stop_orders` or `track_order`, which it replaces.
- **Only what moved is written** (`_apply_layout`): new tracks start on a parked
  `'!'+id` rank; a track whose stop list changed has its stops parked on
  `'!'+id` under their new track, then ranked with `n_keys_between` — the same
  two phases as `_two_phase_renumber`, so a moved stop never meets a
  destination's live rank; the track ranks are rewritten only when the sequence
  changed.
- **Emptied tracks go before the track renumber** — a kept track's new key can
  be one a leaving track still holds — and each one's `stops` collection is
  expired first: `Track.stops` cascades delete-orphan, and a collection loaded
  before the moves would delete the moved stops with their old track
  (`test_a_loaded_track_does_not_take_its_moved_stop_with_it`).
- `segments_to_delete`, the totals and the answer are the endpoint's as before:
  one transaction, `?return=itinerary` answered like every trip edit.

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
| POST | `/itineraries/{id}/reorder` | `require_edit_access` | `ReorderRequest` | `ItineraryDetail` + ETag | 422 (ten uncoded messages, plus the schema's) |

**All four take `?return=itinerary`** and then answer `ItineraryEditResponse` —
the whole trip as a GET right after would show it, plus `created_id`, the new
stop's id on a create — with the ETag; a delete answers 200 instead of 204.
See [itineraries.md](itineraries.md) for the envelope and the rules; the app
always asks for it.

**There are no track endpoints.** Tracks are created and destroyed as a
side-effect of stop writes, and reordered through `reorder`.

`StopCreate` placement fields: `track_id?`, `after_stop_id?`, `before_stop_id?`,
`after_track_id?`, `before_track_id?`. Content fields: `place_name` (≤200),
`place_address` (≤400), `lat` (−90..90), `lng` (−180..180), `map_url` (≤500),
`place_type`, `duration_min` (≥0), `cost` (≥0), `is_free`, `notes` (≤2000).

`ReorderRequest` = `{stop_orders: {track_id: [stop_id…]}, track_order?: [...],
layout?: [{track_id: id | null, stop_ids: [stop_id…]}], segments_to_delete: [...]}`
— `layout` excludes the first two. The app sends only `layout` (with
`segments_to_delete`); the other two stay for installed builds.

`TrackResponse` = `{id, itinerary_id, rank, stops: [StopResponse]}`.
`StopResponse` carries `rank` and a nested `annotations` list.

Asked nothing, `reorder` still answers with the bare detail, built after the
commit by the GET's own helper (`_viewer_detail`) rather than from the stale
itinerary; asked for the trip, it answers the same envelope as every other
trip edit.

## Flutter surface

- **Screens** — `StopFormScreen` (`/itineraries/:id/stops/new`,
  `/itineraries/:id/stops/:stopId/edit`), `StopDetailScreen`
  (`/itineraries/:id/stops/:stopId`), `MapPickerScreen` (`/map-picker`).
- **Arrange mode is the one place a trip's structure changes** — the order of
  its tracks, the order of a track's alternatives, and which track a stop is in.
  The stop list header's button (four arrows, **Arrange stops**, shown in edit
  mode when there are two tracks or a track with alternatives) turns the list
  into `ArrangeTripView` (`widgets/arrange_trip_view.dart`): a row per track,
  a chip per stop. A chip's handle drags at once (it never scrolls the page),
  holding the chip drags too, and a tap picks it for a second tap on where it
  goes; a track's number moves the whole track the same two ways. Targets: a
  gap between tracks (a track of its own; a stop alone in its track moves the
  track instead), a track (its last alternative — by tap, its free space or its
  **Add as alternative** tag), and for a drag only a stop (in front of it —
  inside its own track, a reorder). A tap on another stop or number picks that
  one instead — a second tap says what to move, never where — and a tap on the
  picked one puts it down. A full track (`Track.maxParallelStops`)
  refuses with "Full 4/4". There are no reorder or move buttons on the stop
  cards; `+ // stop` is the only one left.
- **Lifting moves nothing; a drag opens its targets once it is under way.**
  Until a drag has travelled past the touch slop nothing on the list changes:
  the faded copy left in the stop's place keeps the chip's size, a tap's pick
  stays drawn, and no gap, tag or edge auto-scroll appears. A stop held still
  and let go therefore stays where it is — its own chip catches it and changes
  nothing — even under a finger that trembles. (Targets used to open at the
  lift, which pushed the rows down under a still finger; the next tremble
  dropped the stop wherever that landed.) A handle drag starts past the slop,
  so its targets open at once. Every drag ends through `onDragCompleted` /
  `onDraggableCanceled`, never `onDragEnd`, which Flutter skips once the dragged
  widget has been rebuilt away: a row's hover tint did that, and the view stayed
  stuck mid-drag — the stop highlighted, every target open. The stop or track
  being moved is announced as selected to screen readers.
- **Nothing saves until Save.** The arrangement is `TripArrangement`
  (`domain/trip_arrangement.dart`, immutable, every move a pure function); the
  header's ✕ and **Save** replace its button while arranging, everything above
  the list is dimmed and ignores touch (`_InertWhileArranging`), the map and
  pull-to-refresh are off, and Back leaves arrange mode — asking first when the
  arrangement holds something unsaved. Save sends `toLayoutJson()` through
  `ItineraryDetailNotifier.applyArrangement` — one `POST /reorder`, adopted like
  every save, no reload. A 412 or another error keeps the arrangement on screen;
  a lost claim (409) also puts the lock banner above the rows, which is why
  Save went grey, and taking the claim back keeps the arrangement. Regression
  tests: `test/widgets/arrange_mode_test.dart`, `test/models/trip_arrangement_test.dart`.
- **Transport an arrangement breaks is shown as it happens**:
  `computeOrphansForLayout` runs on every move, marks each broken segment under
  its track and sums them up above the rows; Save confirms them and sends them
  as `segments_to_delete`. See [transit-segments.md](transit-segments.md).
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
  keeps the start/middle/end color (`_markerColors`). Arrange mode's chips
  wear the type's icon too; its track numbers stay neutral, since a track can
  mix types. Regression test:
  `test/widgets/stop_card_place_type_test.dart`.
- **Any editing route claims the edit lock before pushing.** `_openStopForm` does
  the round trip first and abandons the push if the claim is refused — no form
  claims a lock for itself, so a route pushed without one looks editable and then
  428s on Save. The stop page (`StopDetailScreen`) shows its edit chrome to
  editors too, and editing from it enters the trip's edit mode — the claim is
  kept, and a trip someone else holds answers with a pop-up that offers the
  takeover when allowed. See [collaborative-editing.md](collaborative-editing.md).
- **A stop save is one request, and its queued notes one each.** The stop's
  answer is the whole trip, adopted as it is; `addStop` returns the stop the
  answer's `created_id` names, and each queued note attaches to it and is
  adopted the same way — a stop with two notes is three requests and no GET
  (`test/widgets/stop_form_queued_notes_test.dart`). Until 2026-10-21 each of
  those writes was followed by a full reload of the trip.
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
  notes use `ExpandableText`, whose "view more" overflow check is a
  `LayoutBuilder`, which throws on an intrinsic query: from May until 2026-09-29
  every parallel track with notes collapsed to 0 px in view mode and re-threw on
  each relayout, freezing the app. Regression test:
  `test/widgets/parallel_stop_group_layout_test.dart`.
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
- **No server-side cap on alternatives per track.** `Track.maxParallelStops`
  (4) is enforced by the client alone — the add-parallel button and arrange
  mode's drop targets. `add_stop`, a stop move and `layout` all accept more.
- The reorder endpoint's ten 422s carry no error code, so the client shows the
  server's English `detail`. With a matching `If-Match` the server holds exactly
  the trip the client arranged, so they can only mean a client bug.

## Related

- [itineraries.md](itineraries.md) — the parent, and the totals these feed
- [transit-segments.md](transit-segments.md) — segments join two stops
- [annotations.md](annotations.md) — stop-level notes hang off `stops`
- [collaborative-editing.md](collaborative-editing.md) — the write guard and lock
- [etag-concurrency.md](etag-concurrency.md) — why bad anchors answer 412
- [text-moderation.md](text-moderation.md) — stop name, address and notes are scanned
- [translations.md](translations.md) — stop notes carry `source_lang` (never the place name); deleting a stop purges what cascaded
- [help-centre.md](help-centre.md) — `/help/plan-alternative-options` describes arrange mode to users
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
