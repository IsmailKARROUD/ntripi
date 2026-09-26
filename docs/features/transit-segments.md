# Transit segments and transport legs

**Status:** shipped (partial — see Known gaps)
**Tables:** `transit_segments`, `transport_legs`
**Config:** none

## Purpose

A **segment** describes how you get from one stop to the next. A **leg** is one
mode-hop inside that journey ("walk 5 min, then metro line 4, then walk 3 min").
Legs carry their own cost, duration and notes, and the segment's totals are the
sum of them.

## Rules

- **A segment is identified by its endpoints**, not by position: UNIQUE
  `uq_segment_stops (from_stop_id, to_stop_id)` plus CHECK
  `ck_segment_different_stops`. A second segment between the same pair answers
  409 `segment_already_exists`.
- **Leg positions must be contiguous `1..n`.** `TransitSegmentCreate._validate_legs`
  (`schemas/itinerary.py:358`) enforces it, and `legs` has `min_length=1` — a
  segment cannot be created without at least one leg.
- **`PATCH /segments/{id}` is a full replace**: it deletes every leg and
  re-inserts from the body. The Flutter client uses only this, never the
  individual leg endpoints.
- **`TransportLegUpdate` deliberately omits `position`**
  (`schemas/itinerary.py:319`) — reordering a leg happens through the segment
  replace, so a per-leg position write would have to defend the UNIQUE
  constraint for no gain.
- **Totals recalculate after every leg or segment mutation**:
  `_recalculate_segment_totals` (`itineraries.py:309`) then
  `_recalculate_totals` on the itinerary. Costs sum only non-`is_free` legs.
- **All leg text goes to the moderation provider in one call.**
  `_leg_text_fields` (`itineraries.py:219`) flattens every leg's `line`,
  `direction` and `notes` into a single request rather than one per leg.
- Segments are listed sorted by `(from_stop.track.rank, from_stop.rank)`.
- `_require_stops_in_itinerary` (`itineraries.py:243`) checks both stops belong
  to the itinerary in the URL — the membership guard.
- **Inserting a track between two segment-joined tracks orphans the segment.**
  The client warns first and deletes the segment(s) on confirm; `reorder` accepts
  `segments_to_delete` so it happens in the same transaction.

## Data model

`transit_segments` — `from_stop_id` / `to_stop_id` both FK → `stops.id` CASCADE.
Only `to_stop_id` has its own index (`ix_transit_segments_to_stop_id`, added in
`a681984a1a04`); `from_stop_id` leads `uq_segment_stops` and can use that.

`transport_legs` — `position` SMALLINT, UNIQUE `uq_leg_position (segment_id,
position)`. **Legs are the one place an integer position survives**; stops use
fractional ranks.

- CHECK `ck_leg_mode` — 11 modes: `walk, bus, tram, metro, train, taxi, uber,
  bike, ferry, car, airplane` (`airplane` added in `a6b7c8d9e0f1`).
- CHECK `ck_leg_note_type` — nullable, or one of the four annotation types
  (added in `b0c1d2e3f4a5`).

ORM: `Stop.outgoing_segment` / `Stop.incoming_segment` are `uselist=False` with
`cascade="all, delete-orphan"`.

Full columns: [reference/data-model.md](../reference/data-model.md#transit_segments).

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/{id}/segments` | verified email **+** `require_edit_access` | `TransitSegmentCreate` | `TransitSegmentResponse` 201 | 400 (uncoded) stop not in itinerary, 409 `segment_already_exists`, 422 non-contiguous legs |
| GET | `/itineraries/{id}/segments` | user | — | `list[TransitSegmentResponse]` | 403 `itinerary_access_denied` |
| PATCH | `/itineraries/{id}/segments/{seg}` | `require_edit_access` | `TransitSegmentCreate` (**full replace**) | `TransitSegmentResponse` | 404 `segment_not_found`, 409 `segment_already_exists` |
| DELETE | `/itineraries/{id}/segments/{seg}` | `require_edit_access` | — | 204 | 404 `segment_not_found` |
| POST | `…/segments/{seg}/legs` | verified email **+** `require_edit_access` | `TransportLegCreate` | `TransportLegResponse` 201 | 409 (uncoded) duplicate position |
| PATCH | `…/segments/{seg}/legs/{leg}` | `require_edit_access` | `TransportLegUpdate` | `TransportLegResponse` | 404 `leg_not_found` |
| DELETE | `…/segments/{seg}/legs/{leg}` | `require_edit_access` | — | 204 | 404 `leg_not_found` |

`TransitSegmentCreate` = `{from_stop_id, to_stop_id, legs: [TransportLegCreate]}`
with `legs` `min_length=1`.
Leg fields: `position`, `mode`, `line` (≤30), `direction` (≤200), `duration_min`,
`cost`, `is_free`, `notes` (≤1000), `note_type`.

**Four of these seven endpoints have no client.** `GET /segments` is unused
because Flutter reads segments from the itinerary detail payload, and the three
`/legs` endpoints are unused because the segment PATCH does a full replace.
`api_endpoints.dart:199` and `social_api/README.md:328` both say so: *"These
endpoints are defined in the backend for future API consumers."*

## Flutter surface

- **`SegmentFormScreen` is dead code.** The whole file body
  (`features/itineraries/presentation/segment_form_screen.dart:12` onward) is
  wrapped in a `/* */` block with `//--TODO: In the future we could consider
  deleting this from because no need of it.` above it. It is the only
  commented-out block in `lib/`. Left behind by commit `7025987` (2026-05-05,
  *"bypass the concept of segement"*). The two files that appear to reference it
  mention it in comments only.
- Segments are edited through sheets and tiles instead:
  `leg_tile.dart`, and the segment rows inside `ItineraryDetailScreen`.
- **Models** — `TransitSegment`, `TransportLeg`
  (`features/itineraries/domain/`), manual `fromJson`/`toJson`.
- `core/services/segment_orphan_service.dart` computes which segments a track
  insertion would orphan, feeding the confirmation dialog.

## Known gaps / TODOs

- **A documented invariant is not actually enforced:**
  `models/transit_segment.py:5` asserts a segment "lives strictly between two
  adjacent stops (`from_stop.position + 1 == to_stop.position`)". The `position`
  column was removed by `d5e6f7a8b9c0`, and `_require_stops_in_itinerary` checks
  only itinerary membership. **Adjacency is enforced nowhere.**
- **Deleting a segment's last leg deletes the segment** (`delete_leg`, since
  2026-09-26), which is what `models/transport_leg.py:20` always claimed. With
  `legs` at `min_length=1` on create and update, a zero-leg segment is no longer
  reachable at all.
- **`social_flutter/README.md` still presents transit segments as a current
  feature** after `7025987` bypassed the concept in the UI.
- The 409 on a duplicate leg position is a bare `HTTPException`
  (`itineraries.py:2172`) with no error code.
- Dead file to delete: `segment_form_screen.dart`.

## Related

- [tracks-and-stops.md](tracks-and-stops.md) — the endpoints a segment joins
- [itineraries.md](itineraries.md) — segments feed the denormalised totals
- [collaborative-editing.md](collaborative-editing.md) — the write guard
- [text-moderation.md](text-moderation.md) — leg line/direction/notes are scanned
- [annotations.md](annotations.md) — `note_type` reuses the same four types
- [backlog.md](../backlog.md)
- [reference/data-model.md](../reference/data-model.md)

## OPEN QUESTIONS

- **Is stop adjacency still an intended invariant?** The model docstring says
  yes, the schema cannot express it any more, and no code checks it. Either the
  comment is stale or a check is missing; the code does not say which.
- **Is a zero-leg segment acceptable?** It is reachable, its totals would be 0,
  and nothing cleans it up.
- **Should the four client-less endpoints stay?** They are documented as "for
  future API consumers" in two places, but there is no other consumer and no
  public API programme.
