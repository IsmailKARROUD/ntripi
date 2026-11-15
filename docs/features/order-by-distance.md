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

- **The cost table** is built in one place, `PathCosts.of`: the trip builds
  it with `straightLineMetres`, the tests with points on a line or a plane. A
  movable block's points are never null by type, so a block nothing locates
  cannot reach the search.
- **Up to 12 movable blocks: exact Held-Karp** (`bestOrder` makes the switch).
  - Every step, the first and the last included, scores
    `d × 256 + popcount(visited blocks above it)`. Among equally short orders,
    the one inverting least of the user's order wins; on a tie, the user's own
    order.
  - The metres are `score ~/ 256`. At most 120 inversions are counted, under
    256.
  - Scores live in a `Float64List`, because `Int64List` is unsupported on the
    web. The largest score (≈10¹¹) is exact below 2⁵³.
  - The function itself takes up to 16 blocks (`kOrderExactLimit`). The tests
    use it at 13–16 blocks as the exact answer the local search is held to.
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
- **Nothing is worked out before the tap, and no trip is too big.** The
  button is shown in arrange mode from three tracks (with two, either order is
  as short), with no upper limit (the owner's choice, decisions.md
  2026-11-15). The work runs on the tap, `async` (the web has no isolates).
  - Every combination of the three answers is worked out then: up to eight,
    four with no live transit segment, and half that when the first track has
    no location. Choices that come to the same thing are worked out once.
  - **The screen gets a turn about once a frame** (`kOrderYieldEveryMs`,
    16 ms): the local search pauses between moves and between kicks, and a
    pause hands the event loop a turn only once 16 ms have passed. That keeps
    the spinner turning and Cancel heard on any size of trip.
    - A turn at every pause would cost a browser at least 4 ms each, once its
      timers nest: 100 pauses took 0.46 s in Edge, against 8 ms on the VM
      (2026-11-15).
    - The clock decides only when the screen gets a turn, never how much work
      is done, so every device still gives the same answer.
  - Times for all four choices, on the development Mac (2026-11-15):

    | Tracks | AOT | dart2js `-O2` |
    |---|---|---|
    | 12 | 7 ms | 25 ms |
    | 40 | 0.33 s | 0.44 s |
    | 60 | 1.2 s | 1.5 s |

    It roughly doubles with a live transit segment (eight choices). A phone
    can be two or three times slower; the device test prints its own.
  - The browser *test runner* is about 30 times slower, because it compiles
    without release optimisation: 60 tracks took 50 s there.

## Data model

None. The suggestion is a reordered `TripArrangement` (`withRowOrder`), saved
as arrange mode's `layout` plus `segments_to_delete`.

## API surface

None of its own — `POST /itineraries/{id}/reorder` with `layout`, exactly as
arrange mode's Save ([tracks-and-stops.md](tracks-and-stops.md)).

## Flutter surface

- **`OrderByDistanceButton`** (`widgets/order_by_distance_sheet.dart`), above
  the arrange rows from three tracks.
  - On a tap it reads "Working out an order…" with a spinner and a **Cancel**
    beside it, until the answer is in. Meanwhile everything else waits: the
    page above is dimmed, the rows take no touch, and the header's ✕ and Save
    are disabled. Cancel, like Back, stops the work and leaves arrange mode as
    it was; an answer that lands afterwards is dropped.
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
- **Tests**, after the owner's 35-item specification (2026-11-15):
  - `test/models/order_by_distance_solver_test.dart`: the solver alone, on a
    line or a plane, through `PathCosts.of`.
    - Edge cases, the exact search against brute force (840 days), and the
      local search's line, grid and rectangle cases.
    - The building blocks: the generator, 2,000 kicks per size, and every
      move's own change held to the path measured again through the steps'
      `MoveProbe`.
    - The rules every answer keeps. On the VM only: the heavy batches, no
      crossings, and at least 95% as short as the exact search at 13, 14 and
      16 blocks.
  - `test/models/order_by_distance_test.dart`: whole trips. What is read and
    moved; lengths measured again from the stops; tracks nothing locates;
    transit segments kept whole; distances of 20,000 km; and
    `straightLineMetres`.
  - `test/models/order_by_distance_golden_test.dart`: 30 fixed trips
    (`test/support/order_by_distance_days.dart`), every choice, held to
    `order_by_distance_golden.dart`, on the VM and in the browser.
    - Rewrite the golden file on purpose only, with
      `order_by_distance_golden_writer_test.dart` and
      `--dart-define=UPDATE_ORDER_GOLDEN=true`.
    - On a phone, run `integration_test/order_by_distance_device_test.dart`
      (`flutter drive --profile`), which also prints its timings.
  - `test/speed/order_by_distance_speed_test.dart`: 12 and 60 tracks,
    budgets about ten times what each runner measured. Skipped unless run
    with `--dart-define=ORDER_SPEED=true`.
  - `test/widgets/order_by_distance_test.dart`: the flow, Cancel included.

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
