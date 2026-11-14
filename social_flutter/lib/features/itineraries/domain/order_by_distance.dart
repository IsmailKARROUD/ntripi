// domain/order_by_distance.dart — Order by distance: a trip's tracks put in
// the order that is shortest in straight lines, worked out on the device.
//
// WHAT IT READS: only coordinates a stop stores itself — an OpenStreetMap
// pick, a map pin, typed coordinates. Never a Google place and never the
// coordinates in a Google Maps link's text: both are Google's content
// (decisions.md 2026-10-31), which is why this never goes through mapPointOf.
//
// WHAT IT MOVES: whole tracks, never a stop out of its track. A track is
// measured from its first alternative with saved coordinates; one with none
// stays after the track before it, and with `keepLegs` two tracks joined by a
// transit segment move as one block, in their direction. The first track stays
// first, and the last stays last when `keepEnd` says so.
//
// HOW: an open-path asymmetric travelling salesman over the blocks, in whole
// metres — exact (Held-Karp) up to 12 movable blocks, an iterated local search
// above. Deterministic by construction: whole metres, a fixed seed, a fixed
// amount of work and never a time limit, so every device gives the same
// answer. A result counts only when it is clearly shorter (kOrderMinGain…).

import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/services/segment_orphan_service.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

/// A suggestion must save at least this many metres…
const kOrderMinGainMetres = 200;

/// …and at least this share of the current length, in percent — so the button
/// never offers a reshuffle for a few metres of straight line.
const kOrderMinGainPercent = 3;

/// Above this many movable blocks the exact search gives way to the local
/// search: Held-Karp is O(m²·2^m), about 2 ms at 12 and 400 times that at 20.
const kOrderExactMaxBlocks = 12;

/// Perturbations of the iterated local search — a fixed count, never a time
/// budget, so a slower phone does not get a different answer.
const kOrderKicks = 100;

/// The kicks' generator seed. Never 0: xorshift's state 0 stays 0 forever.
const kOrderSeed = 12345;

/// One way to answer the sheet: whether the last track stays last, and
/// whether tracks joined by a transit segment stay together.
class OrderChoice {
  const OrderChoice({required this.keepEnd, required this.keepLegs});

  final bool keepEnd;
  final bool keepLegs;

  static const all = [
    OrderChoice(keepEnd: true, keepLegs: true),
    OrderChoice(keepEnd: true, keepLegs: false),
    OrderChoice(keepEnd: false, keepLegs: true),
    OrderChoice(keepEnd: false, keepLegs: false),
  ];

  @override
  bool operator ==(Object other) =>
      other is OrderChoice &&
      other.keepEnd == keepEnd &&
      other.keepLegs == keepLegs;

  @override
  int get hashCode => Object.hash(keepEnd, keepLegs);

  @override
  String toString() => 'OrderChoice(keepEnd: $keepEnd, keepLegs: $keepLegs)';
}

/// What one choice suggests.
class DistanceOrder {
  const DistanceOrder({
    required this.arrangement,
    required this.wasNumber,
    required this.unmeasured,
    required this.brokenLegs,
    required this.lengthMetres,
    required this.previousLengthMetres,
  });

  /// The arrangement with its rows in the suggested order; nothing else moved.
  final TripArrangement arrangement;

  /// The old number (1-based) of each row someone would have to move by hand
  /// to get here: the rows outside the longest run that keeps its old order.
  /// Moving one track to the front is one move, not every track it pushed.
  final Map<String, int> wasNumber;

  /// Tracks after the first with no stop holding saved coordinates; each one
  /// stays after the track before it.
  final int unmeasured;

  /// Every transit segment the suggested order breaks — what the save deletes.
  final List<TransitSegment> brokenLegs;

  /// Straight-line lengths, never shown: a straight line cannot say what the
  /// traveller gains on the road.
  final int lengthMetres;
  final int previousLengthMetres;

  int get moved => wasNumber.length;

  List<String> get rowKeys => [for (final r in arrangement.rows) r.key];
}

/// Why a tap found nothing to suggest.
enum NoOrderReason {
  /// Fewer than two tracks after the first have a saved location.
  tooFewLocated,

  /// No choice gives a clearly shorter order.
  alreadyInOrder,
}

/// Every choice's answer for one arrangement, worked out once on the tap.
class DistanceOrderChoices {
  DistanceOrderChoices._(
    this._results, {
    required this.legsLive,
    required this.located,
    required this.total,
    required this.tooFewLocated,
  });

  final Map<OrderChoice, DistanceOrder?> _results;

  /// Some transit segment joins two neighbouring tracks as they stand — the
  /// only case where keeping legs and deleting them can differ.
  final bool legsLive;

  /// Tracks with a stop holding saved coordinates, out of [total].
  final int located;
  final int total;

  final bool tooFewLocated;

  /// The answer for [choice]; null when it suggests nothing better.
  DistanceOrder? resultFor(OrderChoice choice) => _results[legsLive
      ? choice
      : OrderChoice(keepEnd: choice.keepEnd, keepLegs: false)];

  bool get hasSuggestion => _results.values.any((r) => r != null);

  /// Whether where the trip ends changes the answer, for some legs choice.
  bool get endMatters => const [true, false].any((legs) => !_same(
      resultFor(OrderChoice(keepEnd: true, keepLegs: legs)),
      resultFor(OrderChoice(keepEnd: false, keepLegs: legs))));

  /// Whether keeping linked tracks together changes the answer, for some end.
  bool get legsMatter =>
      legsLive &&
      const [true, false].any((end) => !_same(
          resultFor(OrderChoice(keepEnd: end, keepLegs: true)),
          resultFor(OrderChoice(keepEnd: end, keepLegs: false))));

  NoOrderReason? get reason => hasSuggestion
      ? null
      : tooFewLocated
          ? NoOrderReason.tooFewLocated
          : NoOrderReason.alreadyInOrder;

  static bool _same(DistanceOrder? a, DistanceOrder? b) {
    if (a == null || b == null) return a == null && b == null;
    final ka = a.rowKeys, kb = b.rowKeys;
    if (ka.length != kb.length) return false;
    for (var i = 0; i < ka.length; i++) {
      if (ka[i] != kb[i]) return false;
    }
    return true;
  }
}

/// Order by distance for [arrangement], every choice at once. Runs on the tap,
/// never before, and yields to the event loop between kicks so the screen
/// keeps drawing on every platform (the web has no isolates). Answers null
/// when [isCancelled] says so at one of those pauses.
Future<DistanceOrderChoices?> orderByDistanceChoices(
  TripArrangement arrangement,
  List<TransitSegment> segments, {
  bool Function()? isCancelled,
}) async {
  final trip = _Trip.of(arrangement, segments);
  Future<void> pause() async {
    await Future<void>.delayed(Duration.zero);
    if (isCancelled?.call() ?? false) throw const _Cancelled();
  }

  final results = <OrderChoice, DistanceOrder?>{};
  try {
    for (final choice in OrderChoice.all) {
      // With no live segment, keeping legs and deleting them are one choice.
      if (!trip.legsLive && choice.keepLegs) continue;
      results[choice] = await _suggest(trip, choice, pause);
    }
  } on _Cancelled {
    return null;
  }
  return DistanceOrderChoices._(
    results,
    legsLive: trip.legsLive,
    located: trip.located,
    total: arrangement.rows.length,
    // The freest choice still has fewer than two blocks to put in order.
    tooFewLocated: trip.measuredAfterFirst < 2,
  );
}

class _Cancelled implements Exception {
  const _Cancelled();
}

// ── The trip as points and links ─────────────────────────────────────────────

class _Trip {
  _Trip._(this.arrangement, this.segments, this.points, this.linkedToPrevious);

  factory _Trip.of(TripArrangement arrangement, List<TransitSegment> segments) {
    final rows = arrangement.rows;
    final points = [for (final r in rows) _pointOf(r.stops)];
    // A segment live in the arrangement as it stands joins row i to row i+1.
    final orphans = {
      for (final s in computeOrphansForLayout(
          layout: arrangement.tracks, segments: segments))
        s.id,
    };
    final rowOfStop = {
      for (var i = 0; i < rows.length; i++)
        for (final s in rows[i].stops) s.id: i,
    };
    final linked = List<bool>.filled(rows.length, false);
    for (final seg in segments) {
      if (orphans.contains(seg.id)) continue;
      final from = rowOfStop[seg.fromStopId];
      final to = rowOfStop[seg.toStopId];
      if (from != null && to != null && to == from + 1) linked[to] = true;
    }
    return _Trip._(arrangement, segments, points, linked);
  }

  final TripArrangement arrangement;
  final List<TransitSegment> segments;

  /// Row i's point, or null when none of its stops stores coordinates.
  final List<LatLng?> points;

  /// Row i is joined to row i−1 by a live transit segment.
  final List<bool> linkedToPrevious;

  bool get legsLive => linkedToPrevious.any((l) => l);

  int get located => points.where((p) => p != null).length;

  int get measuredAfterFirst =>
      points.skip(1).where((p) => p != null).length;

  /// The rows as blocks that move whole: a row joins the block before it when
  /// it has no point, or when [keepLegs] and a segment links it to that block.
  List<_Block> blocks({required bool keepLegs}) {
    final blocks = <_Block>[];
    for (var i = 0; i < points.length; i++) {
      final glued =
          i > 0 && (points[i] == null || (keepLegs && linkedToPrevious[i]));
      if (glued) {
        blocks.last.last = i;
      } else {
        blocks.add(_Block(i));
      }
    }
    for (final b in blocks) {
      for (var i = b.first; i <= b.last; i++) {
        final p = points[i];
        if (p == null) continue;
        b.entry ??= p;
        b.exit = p;
      }
    }
    return blocks;
  }
}

/// The first stop that stores its own coordinates. A stop with a Google place
/// or a map link never does on the server (`ck_stops_place_id_no_coords`,
/// `ck_stops_link_no_coords`); checking keeps that true for any Stop.
LatLng? _pointOf(List<Stop> stops) {
  for (final s in stops) {
    final lat = s.lat, lng = s.lng;
    if (lat == null || lng == null) continue;
    if (s.googlePlaceId != null || s.mapUrl != null) continue;
    return LatLng(lat, lng);
  }
  return null;
}

/// Rows first..last, which move as one; entered at its first point, left at
/// its last. Only the first block can have neither.
class _Block {
  _Block(this.first) : last = first;

  final int first;
  int last;
  LatLng? entry;
  LatLng? exit;
}

int _metres(LatLng a, LatLng b) => const Haversine().distance(a, b).round();

// ── One choice ───────────────────────────────────────────────────────────────

Future<DistanceOrder?> _suggest(
  _Trip trip,
  OrderChoice choice,
  Future<void> Function() pause,
) async {
  final blocks = trip.blocks(keepLegs: choice.keepLegs);
  final hasEnd = choice.keepEnd && blocks.length > 1;
  final movable =
      blocks.sublist(1, hasEnd ? blocks.length - 1 : blocks.length);
  final m = movable.length;
  // Nothing to put in order: the input order, which suggests nothing.
  if (m < 2) return null;

  final d = _pathCosts(
    start: blocks.first,
    movable: movable,
    end: hasEnd ? blocks.last : null,
  );
  final order = m <= kOrderExactMaxBlocks
      ? exactOrder(d)
      : await localSearchOrder(d, pause: pause);

  final before = d.lengthOf(d.identity());
  final after = d.lengthOf(order);
  final gain = before - after;
  if (gain < kOrderMinGainMetres || gain * 100 < kOrderMinGainPercent * before) {
    return null;
  }

  final rows = trip.arrangement.rows;
  final keys = <String>[];
  void addBlock(_Block b) {
    for (var i = b.first; i <= b.last; i++) {
      keys.add(rows[i].key);
    }
  }

  addBlock(blocks.first);
  for (var t = 1; t <= m; t++) {
    addBlock(movable[order[t] - 1]);
  }
  if (hasEnd) addBlock(blocks.last);

  final suggested = trip.arrangement.withRowOrder(keys);
  final oldIndex = {for (var i = 0; i < rows.length; i++) rows[i].key: i};
  final sequence = [for (final k in keys) oldIndex[k]!];
  final kept = longestIncreasingRun(sequence);
  return DistanceOrder(
    arrangement: suggested,
    wasNumber: {
      for (var i = 0; i < keys.length; i++)
        if (!kept.contains(i)) keys[i]: sequence[i] + 1,
    },
    unmeasured: trip.points.skip(1).where((p) => p == null).length,
    brokenLegs: computeOrphansForLayout(
        layout: suggested.tracks, segments: trip.segments),
    lengthMetres: after,
    previousLengthMetres: before,
  );
}

/// The positions (in [sequence]) of one longest strictly increasing run —
/// the rows that keep their old relative order. Patience sorting, so the
/// choice among equally long runs is always the same one.
Set<int> longestIncreasingRun(List<int> sequence) {
  final tails = <int>[]; // tails[l] = position ending the best run of l+1
  final previous = List<int>.filled(sequence.length, -1);
  for (var i = 0; i < sequence.length; i++) {
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sequence[tails[mid]] < sequence[i]) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) previous[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final run = <int>{};
  for (var i = tails.isEmpty ? -1 : tails.last; i >= 0; i = previous[i]) {
    run.add(i);
  }
  return run;
}

// ── Path costs ───────────────────────────────────────────────────────────────

/// Whole-metre costs between the nodes of one path: node 0 is the fixed start,
/// 1..m the movable blocks in input order, m+1 the end — the fixed last block,
/// or a virtual end that costs 0 to reach when the trip may end anywhere.
/// Going from a block to another costs the distance from its exit to the
/// other's entry; a start with no point costs 0 to leave.
class PathCosts {
  PathCosts(this.m, this._d) : assert(_d.length == (m + 2) * (m + 2));

  /// From a full (m+2)×(m+2) table of metres — what the tests build.
  factory PathCosts.fromRows(List<List<int>> rows) => PathCosts(
      rows.length - 2, Int32List.fromList([for (final r in rows) ...r]));

  /// Movable blocks; the path has m+2 nodes.
  final int m;
  final Int32List _d;

  /// The table itself, row-major over m+2 nodes — what the scans index
  /// directly: a call per lookup is most of their time in a browser.
  Int32List get table => _d;

  int call(int u, int v) => _d[u * (m + 2) + v];

  /// [0, 1, …, m, m+1]: the blocks as they stand.
  List<int> identity() => [for (var i = 0; i <= m + 1; i++) i];

  int lengthOf(List<int> path) {
    var total = 0;
    for (var t = 0; t + 1 < path.length; t++) {
      total += this(path[t], path[t + 1]);
    }
    return total;
  }
}

PathCosts _pathCosts({
  required _Block start,
  required List<_Block> movable,
  required _Block? end,
}) {
  final m = movable.length;
  final n = m + 2;
  final d = Int32List(n * n);
  LatLng? exitOf(int u) => u == 0 ? start.exit : movable[u - 1].exit;
  LatLng? entryOf(int v) => v == m + 1 ? end?.entry : movable[v - 1].entry;
  for (var u = 0; u <= m; u++) {
    final from = exitOf(u);
    if (from == null) continue; // a start nothing locates: free to leave
    for (var v = 1; v <= m + 1; v++) {
      if (u == v) continue;
      final to = entryOf(v);
      if (to == null) continue; // the virtual end
      d[u * n + v] = _metres(from, to);
    }
  }
  return PathCosts(m, d);
}

// ── Exact: Held-Karp ─────────────────────────────────────────────────────────

/// popcount of every 12-bit mask. Dart 3.12 has no int.oneBitCount, and the
/// pubspec floor is 3.7; switch once the floor reaches an SDK that has it.
final Uint8List _popcount = () {
  final t = Uint8List(1 << kOrderExactMaxBlocks);
  for (var x = 1; x < t.length; x++) {
    t[x] = t[x >> 1] + (x & 1);
  }
  return t;
}();

/// The shortest path through every movable block, exactly. Every step scores
/// `d × 256 + popcount(visited above it)` — the first and last steps too, as
/// `d × 256` — so among equally long orders the one with the fewest
/// inversions of the input order wins: on a tie, the user's order. At most 66
/// inversions are ever counted (under 256), so the metres are `score ~/ 256`.
/// Scores live in a Float64List: Int64List is unsupported on the web, and the
/// largest score (≈7×10¹⁰) is exact below 2⁵³.
List<int> exactOrder(PathCosts d) => exactOrderWithScore(d).order;

/// [exactOrder] with its winning score — whose `~/ 256` is its length.
({List<int> order, double score}) exactOrderWithScore(PathCosts d) {
  final m = d.m;
  if (m < 2) {
    final order = d.identity();
    return (order: order, score: d.lengthOf(order) * 256.0);
  }
  assert(m <= kOrderExactMaxBlocks);
  final size = 1 << m;
  final best = Float64List(size * m)..fillRange(0, size * m, double.infinity);
  final parent = Int8List(size * m)..fillRange(0, size * m, -1);
  // Bit j is movable block j+1, in input order.
  for (var j = 0; j < m; j++) {
    best[(1 << j) * m + j] = d(0, j + 1) * 256.0;
  }
  for (var mask = 1; mask < size; mask++) {
    for (var j = 0; j < m; j++) {
      if (mask & (1 << j) == 0) continue;
      final here = best[mask * m + j];
      if (here == double.infinity) continue;
      for (var k = 0; k < m; k++) {
        if (mask & (1 << k) != 0) continue;
        final next = (mask | (1 << k)) * m + k;
        final score = here + d(j + 1, k + 1) * 256.0 + _popcount[mask >> (k + 1)];
        if (score < best[next]) {
          best[next] = score;
          parent[next] = j;
        }
      }
    }
  }
  final full = size - 1;
  var last = -1;
  var bestScore = double.infinity;
  for (var j = 0; j < m; j++) {
    final score = best[full * m + j] + d(j + 1, m + 1) * 256.0;
    if (score < bestScore) {
      bestScore = score;
      last = j;
    }
  }
  final reversed = <int>[];
  for (var mask = full, j = last; j >= 0;) {
    reversed.add(j + 1);
    final p = parent[mask * m + j];
    mask &= ~(1 << j);
    j = p;
  }
  return (order: [0, ...reversed.reversed, m + 1], score: bestScore);
}

// ── Above 12: iterated local search ──────────────────────────────────────────

/// A short, good path through every movable block: local search from the
/// nearest-neighbour order and from the input order (the shorter wins, the
/// input on a tie), then [kOrderKicks] kicks, each a double-bridge — A B C D E
/// becomes A D C B E — and the local search again. The current order may move
/// to a result that is not longer, to cross plateaus; the best order is
/// replaced only by a strictly shorter one, and that is what is returned, so
/// on equal lengths the user's order wins and two runs give the same answer.
/// Never longer than the input order.
Future<List<int>> localSearchOrder(
  PathCosts d, {
  Future<void> Function()? pause,
}) async {
  if (d.m < 2) return d.identity();
  final fromInput = improve(d, d.identity());
  final fromNearest = improve(d, nearestNeighbourOrder(d));
  var current = d.lengthOf(fromInput) <= d.lengthOf(fromNearest)
      ? fromInput
      : fromNearest;
  var currentLength = d.lengthOf(current);
  var best = current;
  var bestLength = currentLength;
  if (d.m < 3) return best; // a kick needs three pieces to move
  final rng = XorShift32(kOrderSeed);
  for (var k = 0; k < kOrderKicks; k++) {
    await pause?.call();
    final candidate = improve(d, doubleBridge(current, rng));
    final length = d.lengthOf(candidate);
    if (length <= currentLength) {
      current = candidate;
      currentLength = length;
    }
    if (length < bestLength) {
      best = candidate;
      bestLength = length;
    }
  }
  return best;
}

/// From the start, always the nearest block not yet visited; ties go to the
/// input order. Never the answer alone: it leaves a far block for last.
List<int> nearestNeighbourOrder(PathCosts d) {
  final m = d.m;
  final visited = List<bool>.filled(m + 1, false);
  final path = [0];
  var here = 0;
  for (var step = 0; step < m; step++) {
    var next = -1;
    var nearest = 0;
    for (var v = 1; v <= m; v++) {
      if (visited[v]) continue;
      final cost = d(here, v);
      if (next < 0 || cost < nearest) {
        next = v;
        nearest = cost;
      }
    }
    visited[next] = true;
    path.add(next);
    here = next;
  }
  return path..add(m + 1);
}

/// Or-opt, 2-opt and swaps, each taking the first move that shortens the
/// path in a fixed scan order, until none does. Blocks never flip — a leg
/// runs entry → exit — so 2-opt only reverses the order blocks are visited in.
List<int> improve(PathCosts d, List<int> path) {
  final p = [...path];
  while (_orOpt(d, p) || _twoOpt(d, p) || _swap(d, p)) {}
  return p;
}

/// Moves a run p[a..b] of any length to a position it is not already in.
bool _orOpt(PathCosts d, List<int> p) {
  final m = d.m, n = m + 2, dd = d.table;
  for (var a = 1; a <= m; a++) {
    final before = p[a - 1] * n, first = p[a];
    for (var b = a; b <= m; b++) {
      if (b - a + 1 >= m) continue; // the whole run has nowhere else to go
      final last = p[b] * n, after = p[b + 1];
      final removed = dd[before + first] + dd[last + after] - dd[before + after];
      for (var t = 0; t <= m; t++) {
        // Between p[t] and p[t+1]; inside or beside the run changes nothing.
        if (t >= a - 1 && t <= b) continue;
        final from = p[t] * n, to = p[t + 1];
        final added = dd[from + first] + dd[last + to] - dd[from + to];
        if (added - removed < 0) {
          final run = p.sublist(a, b + 1);
          final rest = [...p.sublist(0, a), ...p.sublist(b + 1)];
          rest.insertAll((t < a ? t : t - run.length) + 1, run);
          p.setAll(0, rest);
          return true;
        }
      }
    }
  }
  return false;
}

/// Reverses the order p[i..j] is visited in. With F and R the forward and
/// backward costs added up along the path, the change is
///   d(p[i−1]→p[j]) + d(p[i]→p[j+1]) − d(p[i−1]→p[i]) − d(p[j]→p[j+1])
///   + (R[j] − R[i]) − (F[j] − F[i])
/// and below 0 the reversal shortens the path.
bool _twoOpt(PathCosts d, List<int> p) {
  final m = d.m, n = m + 2, dd = d.table;
  final f = List<int>.filled(m + 2, 0);
  final r = List<int>.filled(m + 2, 0);
  for (var k = 0; k <= m; k++) {
    f[k + 1] = f[k] + dd[p[k] * n + p[k + 1]];
    r[k + 1] = r[k] + dd[p[k + 1] * n + p[k]];
  }
  for (var i = 1; i < m; i++) {
    final before = p[i - 1] * n, first = p[i];
    for (var j = i + 1; j <= m; j++) {
      // twoOptChange, written out over the table.
      final last = p[j], after = p[j + 1];
      final change = dd[before + last] +
          dd[first * n + after] -
          dd[before + first] -
          dd[last * n + after] +
          (r[j] - r[i]) -
          (f[j] - f[i]);
      if (change < 0) {
        for (var lo = i, hi = j; lo < hi; lo++, hi--) {
          final t = p[lo];
          p[lo] = p[hi];
          p[hi] = t;
        }
        return true;
      }
    }
  }
  return false;
}

/// The 2-opt change for reversing p[i..j], from prefix sums [f] and [r].
int twoOptChange(
        PathCosts d, List<int> p, int i, int j, List<int> f, List<int> r) =>
    d(p[i - 1], p[j]) +
    d(p[i], p[j + 1]) -
    d(p[i - 1], p[i]) -
    d(p[j], p[j + 1]) +
    (r[j] - r[i]) -
    (f[j] - f[i]);

/// Swaps two blocks.
bool _swap(PathCosts d, List<int> p) {
  final m = d.m, n = m + 2, dd = d.table;
  int c(int u, int v) => dd[u * n + v];
  for (var a = 1; a < m; a++) {
    for (var b = a + 1; b <= m; b++) {
      final int before, after;
      if (b == a + 1) {
        before = c(p[a - 1], p[a]) + c(p[a], p[b]) + c(p[b], p[b + 1]);
        after = c(p[a - 1], p[b]) + c(p[b], p[a]) + c(p[a], p[b + 1]);
      } else {
        before = c(p[a - 1], p[a]) +
            c(p[a], p[a + 1]) +
            c(p[b - 1], p[b]) +
            c(p[b], p[b + 1]);
        after = c(p[a - 1], p[b]) +
            c(p[b], p[a + 1]) +
            c(p[b - 1], p[a]) +
            c(p[a], p[b + 1]);
      }
      if (after < before) {
        final t = p[a];
        p[a] = p[b];
        p[b] = t;
        return true;
      }
    }
  }
  return false;
}

/// Cuts the movable part into A B C D E (B, C and D never empty) and returns
/// A D C B E. The fixed start and end stay outside it.
List<int> doubleBridge(List<int> path, XorShift32 rng) {
  final q = path.sublist(1, path.length - 1);
  final m = q.length;
  final x = rng.nextInt(m - 2); // 0..m-3
  final y = x + 1 + rng.nextInt(m - 2 - x); // x+1..m-2
  final z = y + 1 + rng.nextInt(m - 1 - y); // y+1..m-1
  final w = z + 1 + rng.nextInt(m - z); // z+1..m
  return [
    path.first,
    ...q.sublist(0, x),
    ...q.sublist(z, w),
    ...q.sublist(y, z),
    ...q.sublist(x, y),
    ...q.sublist(w),
    path.last,
  ];
}

/// xorshift32, written out with 32-bit masks: the same numbers on the phone,
/// on the web (whose bitwise operators work on 32 bits) and on every SDK —
/// dart:math's seeded Random may change its stream between releases.
class XorShift32 {
  XorShift32(int seed)
      : assert(seed & 0xFFFFFFFF != 0, 'state 0 stays 0 forever'),
        _state = seed & 0xFFFFFFFF;

  int _state;

  int next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return _state = x & 0xFFFFFFFF;
  }

  /// 0 ≤ n < [max].
  int nextInt(int max) => next() % max;
}
