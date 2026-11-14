# Order by distance

**Status:** shipped (app only)
**Tables:** none
**Config:** none

## Purpose

In arrange mode, **Order by distance** suggests an order for a trip's tracks,
shortest in straight lines between the stops' saved locations. The user sees
the suggestion first and saves it or cancels it. It is worked out on the
device, on phones and on the web alike: nothing is sent anywhere, there is no
backend route, and the save is arrange mode's own single `POST /reorder`
([tracks-and-stops.md](tracks-and-stops.md)). Decided in
[decisions.md](../decisions.md), 2026-11-14.

## Rules

### What it reads

- **Only coordinates a stop stores itself**: `lat`/`lng` from an
  OpenStreetMap pick, a map pin, typed coordinates, or a stop saved before
  `place_source` existed.
- **Never a Google place, and never a Google Maps link's coordinates.**
  A Google pick stores a place ID and no coordinates. A link's own text often
  carries `@lat,lng`, but those are Google's content (decisions.md 2026-10-31).
  That is why the code never goes through `mapPointOf`, which reads link text
  for Google's own route map. `_pointOf` also skips a stop holding coordinates
  beside a place ID or a link, which the server never stores
  (`ck_stops_place_id_no_coords`, `ck_stops_link_no_coords`).
- **No distance is ever shown.** A straight line cannot say what the
  traveller gains on the road, so the sheet and the preview carry no km and
  no percentage.

### What it moves

- **Whole tracks only.** Alternatives keep their order, no stop changes track,
  and no track is split or merged.
- A track is measured from its **first alternative with saved coordinates**.
- **A track with no measurable alternative stays after the track before it.**
  A first track with none has no track before it, so it **stays first**.
- **The start and the end are asked about, each only when the answer changes
  the order**: the first track stays first, or the trip starts wherever fits
  best; the last stays last, or the trip ends wherever fits best. A start or
  an end no answer moves is not asked about (decisions.md, the second
  2026-11-14 entry).
- **Transit segments are asked about, when it matters.** Keeping
  them moves tracks joined by a segment that is live in the arrangement as it
  stands as one block, in their direction. Deleting them lets those tracks move
  apart, and the save then deletes the segments, as any arrange-mode save does.

### How it is worked out

`domain/order_by_distance.dart` solves an open-path asymmetric travelling
salesman problem over the blocks. Going from block A to block B costs the
haversine distance from A's last point to B's first, in **whole metres**. With
a free end the path ends at a virtual end that costs 0 to reach; with a free
start it leaves from a virtual start that costs 0 to leave, and the first block
is one of the movable ones.

- **Up to 12 movable blocks: exact Held-Karp.** Every step, the first and the
  last included, scores `d × 256 + popcount(visited blocks above it)`. Among
  equally short orders, the one inverting least of the user's order wins; on a
  tie, the user's own order. The metres are `score ~/ 256` (at most 66
  inversions, under 256). Scores live in a `Float64List`, because `Int64List`
  is unsupported on the web; the largest score (≈7×10¹⁰) is exact below 2⁵³.
- **Above 12: iterated local search.**
  - It starts from the input order and from the nearest-neighbour order; the
    shorter wins, the input on a tie.
  - Moves: Or-opt (a run of any length moved to every position it is not
    already in), 2-opt (the order a section is visited in reversed; blocks
    never flip) and pairwise swaps, each taking the first improving move.
  - Then **100 double-bridge kicks** (A B C D E → A D C B E). The current
    order may move to a result that is not longer; the returned best order is
    replaced only by a strictly shorter one.
- **Deterministic everywhere.** Whole metres, the seed `12345` (never 0: an
  xorshift state of 0 stays 0), a hand-written xorshift32 with 32-bit masks
  (`dart:math`'s seeded stream may change between SDK releases), a fixed
  number of kicks and **never a time limit**.
- **A suggestion must be clearly shorter**: at least 200 m and at least 3% of
  the current straight-line length (`kOrderMinGainMetres`,
  `kOrderMinGainPercent`), so the button never offers a reshuffle for a few
  metres.
- **Nothing is worked out before the tap.** The button is shown in arrange
  mode from three tracks (with two, either order is as short). The work runs
  on the tap, `async`, yielding between kicks so the screen keeps drawing (the
  web has no isolates).
  - Every combination of the three answers is worked out then: up to eight,
    four with no live transit segment, and half that when the first track has
    no location. Choices that come to the same thing are worked out once.
  - A 40-track trip (four choices) took about 0.35 s in an AOT build and
    0.38 s in release JavaScript (dart2js `-O2`); 60 tracks took 1.4–2 s
    (2026-11-14, on a busy development Mac). With two choices, before the
    start became a question, 40 tracks took 0.15 s.
  - The browser *test runner* is about 30 times slower, because it compiles
    without release optimisation, so the time budget test runs on the VM
    only.

## Data model

None. The suggestion is a reordered `TripArrangement` (`withRowOrder`), saved
as arrange mode's `layout` plus `segments_to_delete`.

## API surface

None of its own — `POST /itineraries/{id}/reorder` with `layout`, exactly as
arrange mode's Save ([tracks-and-stops.md](tracks-and-stops.md)).

## Flutter surface

- **`OrderByDistanceButton`** (`widgets/order_by_distance_sheet.dart`), above
  the arrange rows from three tracks.
  - On a tap it reads "Working out an order…" until the answer is in. Meanwhile
    the rows take no touch, the header's ✕ and Save wait, and Back stops it.
  - A tap that finds no better order says why in a SnackBar: "Only N of M
    tracks have a saved location…" when fewer than three tracks can be
    measured (between two points, either order is as short), otherwise "The
    tracks are already in order by distance".
- **`showOrderByDistanceSheet`** asks **only the questions whose answer changes
  the result**: where the trip starts, where it ends, and whether to keep or
  delete transit segments. When none does, there is no sheet.
  - A start or an end it does not ask about is stated under the title instead:
    "Starts at ‹first›, which stays first." and "Ends at ‹last›, which stays
    last.".
  - The defaults are the careful answers: start kept, end kept, segments kept.
  - If the chosen answers change nothing, Suggest is disabled and the sheet
    says the order stays as it is.
- **The preview** is arrange mode's rows, read-only, in the suggested order
  (`ArrangeTripView(previewWas:)`).
  - Each track a user would have to move by hand carries "was N": the rows
    outside the longest run that keeps its old order.
  - `SuggestedOrderBar` above the rows shows "Suggested order", "N of M tracks
    move", and a note when some tracks have no saved location.
  - When segments will be deleted, arrange mode's own broken-segments banner
    names them.
  - The header's ✕ and Save give way to the bar's **Cancel / Save**, and Back
    is Cancel.
- **Save saves at once**, through the same `_saveArrangement` as arrange
  mode's Save. It does not ask again about segments (the sheet and the preview
  said so), and it leaves arrange mode with "Order saved". Cancel returns to
  arrange mode exactly as it was, the user's earlier moves included. Save is
  gated like arrange mode's: online and holding the claim.
- **`orderByDistanceSolverProvider`** (`providers/order_by_distance_provider.dart`)
  is the solver's seam: `test/widgets/order_by_distance_test.dart` counts its
  calls to hold "nothing before the tap".
- Tests: `test/models/order_by_distance_test.dart` (the solvers, the
  tie-breaks, the 2-opt formula, the pinned generator and a pinned 30-track
  order) and `test/widgets/order_by_distance_test.dart` (the flow).

## Known gaps

- **Straight lines only.** Across water, mountains or a one-way city the road
  order can differ; the user sees the suggestion before saving it.
- **Google picks and Google Maps links are not measured**; they stay after the
  track before them. Google Routes' `optimizeWaypointOrder` would measure them
  through the server — [backlog.md](../backlog.md).
- The help article says which stops can be ordered by distance, but on a trip
  of Google picks only a tap on the button says so.

## Related

- [tracks-and-stops.md](tracks-and-stops.md) — arrange mode, `TripArrangement` and the `layout` save
- [places-and-maps.md](places-and-maps.md) — what a stop may store, and why Google's coordinates stay out
- [transit-segments.md](transit-segments.md) — why a segment lives only between neighbouring tracks
- [collaborative-editing.md](collaborative-editing.md) — the claim the save needs
- [help-centre.md](help-centre.md) — `/help/plan-alternative-options` describes it to users
