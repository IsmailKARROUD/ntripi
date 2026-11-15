// test/support/order_by_distance_fixtures.dart — what the Order by distance
// tests build their days from, and the oracles they are held to.
//
// Two kinds of day:
//   * trips — tracks of stops on the earth, solved through
//     orderByDistanceChoices like the app does;
//   * cost tables — blocks on a line or a plane in whole metres, built
//     through the solver's own PathCosts.of, so the tests use the real
//     exit → entry rule.
// Random days come from XorShift32, never dart:math's Random: its seeded
// stream may differ between the VM and the web, where these days must match.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

// ── Choices ──────────────────────────────────────────────────────────────────

const keepAll = OrderChoice(keepStart: true, keepEnd: true, keepLegs: true);
const freeEnd = OrderChoice(keepStart: true, keepEnd: false, keepLegs: true);
const freeEndNoLegs =
    OrderChoice(keepStart: true, keepEnd: false, keepLegs: false);
const freeStart = OrderChoice(keepStart: false, keepEnd: true, keepLegs: true);
const freeBoth = OrderChoice(keepStart: false, keepEnd: false, keepLegs: true);

/// A choice as three letters — upper case kept, lower case free: start, end,
/// legs. `SEL` keeps all three.
String choiceCode(OrderChoice c) =>
    '${c.keepStart ? 'S' : 's'}${c.keepEnd ? 'E' : 'e'}${c.keepLegs ? 'L' : 'l'}';

// ── Trips ────────────────────────────────────────────────────────────────────

Stop orderStop(
  String id,
  String trackId, {
  double? lng,
  double lat = 0,
  String? googlePlaceId,
  String? mapUrl,
}) =>
    Stop(
      id: id,
      itineraryId: 'itin-1',
      trackId: trackId,
      rank: 'a0',
      type: StopType.waypoint,
      placeName: id,
      lat: lng == null ? null : lat,
      lng: lng,
      googlePlaceId: googlePlaceId,
      mapUrl: mapUrl,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Track orderTrack(String id, List<Stop> stops) =>
    Track(id: id, itineraryId: 'itin-1', rank: id, stops: stops);

/// A track [id] holding one stop of the same name at longitude [lng] on the
/// equator (no coordinates when null), where 0.01° is about 1.1 km.
Track trackAt(String id, double? lng, {double lat = 0}) =>
    orderTrack(id, [orderStop(id, id, lng: lng, lat: lat)]);

/// latlong2's earth radius, which its haversine measures with.
const _earthRadius = 6378137.0;

/// A one-stop track [x] metres east of 0°, on the equator: between two such
/// tracks the haversine reads exactly the difference, in whole metres.
Track trackAtMetres(String id, int x) =>
    trackAt(id, x / _earthRadius * 180 / math.pi);

TransitSegment orderSegment(String id, String fromStopId, String toStopId) =>
    TransitSegment(
      id: id,
      itineraryId: 'itin-1',
      fromStopId: fromStopId,
      toStopId: toStopId,
      totalDurationMin: 10,
      totalCost: 0,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<DistanceOrderChoices> choicesFor(
  List<Track> tracks, {
  List<TransitSegment> segments = const [],
}) async =>
    (await orderByDistanceChoices(TripArrangement.of(tracks), segments))!;

/// [count] one-stop tracks scattered over about 10 km.
List<Track> scatteredTracks(int count, {int seed = 99}) {
  final rng = XorShift32(seed);
  double coordinate() => rng.nextInt(9000) / 100000;
  return [
    for (var i = 0; i < count; i++)
      orderTrack('t$i', [
        orderStop('t$i', 't$i', lat: coordinate(), lng: coordinate()),
      ]),
  ];
}

/// A trip to work out: its tracks, and the transit segments between them.
class TripDay {
  const TripDay(this.name, this.tracks, this.segments);

  final String name;
  final List<Track> tracks;
  final List<TransitSegment> segments;

  TripArrangement get arrangement => TripArrangement.of(tracks);

  /// The tracks a kept segment glues to the track before them: every segment
  /// here runs from one track to the next, as the trip stands.
  Set<String> get gluedByLegs => {
        for (final s in segments)
          tracks.firstWhere((t) => t.stops.any((x) => x.id == s.toStopId)).id,
      };

  /// The keys of the tracks with no point of their own.
  Set<String> get unmeasured => {
        for (final t in tracks)
          if (pointOfTrack(t.stops) == null) t.id,
      };
}

/// A random trip of [count] tracks, from [seed]:
///   * spread over [spanKm] around Brussels, anywhere on the earth from
///     5,000 km, or in three clusters of 600 m;
///   * [unmeasuredPercent] of the tracks without a saved location, in turn
///     none, a Google pick and a link — the first one too when
///     [firstUnmeasured];
///   * [alternativesPercent] of the tracks with two or three alternatives,
///     the first sometimes without a location;
///   * [samePointPercent] of them on a point already used, and with
///     [roundTrip] the last at the first one's point;
///   * [legPercent] of the neighbouring pairs joined by a transit segment.
TripDay randomTrip(
  String name,
  int seed,
  int count, {
  double spanKm = 10,
  bool clustered = false,
  int unmeasuredPercent = 0,
  bool firstUnmeasured = false,
  int alternativesPercent = 0,
  int samePointPercent = 0,
  bool roundTrip = false,
  int legPercent = 0,
}) {
  final rng = XorShift32(seed);
  double unit() => (rng.nextInt(20001) - 10000) / 10000; // −1..1
  final world = spanKm >= 5000;
  (double, double) anywhere() => world
      ? (unit() * 60, unit() * 180)
      : (50.85 + unit() * spanKm / 2 / 111.2, 4.35 + unit() * spanKm / 2 / 70.2);
  final centres = [for (var i = 0; i < 3; i++) anywhere()];
  (double, double) point() {
    if (!clustered) return anywhere();
    final c = centres[rng.nextInt(3)];
    return (c.$1 + unit() * 0.3 / 111.2, c.$2 + unit() * 0.3 / 70.2);
  }

  final used = <(double, double)>[];
  var unmeasuredKind = 0;
  Stop located(String id, String trackId, (double, double) p) =>
      orderStop(id, trackId, lat: p.$1, lng: p.$2);
  Stop unlocated(String id, String trackId) => switch (unmeasuredKind++ % 3) {
        0 => orderStop(id, trackId),
        1 => orderStop(id, trackId, googlePlaceId: 'ChIJ-$id'),
        _ => orderStop(id, trackId,
            mapUrl: 'https://www.google.com/maps/place/$id'),
      };

  final tracks = <Track>[];
  for (var i = 0; i < count; i++) {
    final id = 't$i';
    final unmeasured = (i == 0 && firstUnmeasured) ||
        (i > 0 && rng.nextInt(100) < unmeasuredPercent);
    final p = roundTrip && i == count - 1 && used.isNotEmpty
        ? used.first
        : used.isNotEmpty && rng.nextInt(100) < samePointPercent
            ? used[rng.nextInt(used.length)]
            : point();
    if (!unmeasured) used.add(p);
    final stops = <Stop>[];
    if (unmeasured) {
      stops.add(unlocated('$id-a', id));
    } else if (rng.nextInt(100) < alternativesPercent) {
      // An alternative without a location first, sometimes: the track is
      // measured from the first one that has one.
      if (rng.nextInt(2) == 0) stops.add(unlocated('$id-x', id));
      stops.add(located('$id-a', id, p));
      stops.add(located('$id-b', id, point()));
    } else {
      stops.add(located('$id-a', id, p));
    }
    tracks.add(orderTrack(id, stops));
  }
  final segments = [
    for (var i = 1; i < count; i++)
      if (rng.nextInt(100) < legPercent)
        orderSegment('seg$i', tracks[i - 1].stops.first.id,
            tracks[i].stops.first.id),
  ];
  return TripDay(name, tracks, segments);
}

/// A track's point by the tests' own reading of the rule: its first stop that
/// stores coordinates and is neither a Google place nor a link.
LatLng? pointOfTrack(List<Stop> stops) {
  for (final s in stops) {
    if (s.lat == null || s.lng == null) continue;
    if (s.googlePlaceId != null || s.mapUrl != null) continue;
    return LatLng(s.lat!, s.lng!);
  }
  return null;
}

/// The straight-line length of [rows] in this order, measured again from the
/// stops: the first row starts a block, and so does every other row with a
/// point that is not in [gluedByLegs]; a block is left at its last point and
/// the next entered at its first. A start with no point costs nothing to
/// leave.
int measuredLength(List<ArrangedTrack> rows, {Set<String> gluedByLegs = const {}}) {
  var total = 0;
  LatLng? exit;
  for (var i = 0; i < rows.length; i++) {
    final p = pointOfTrack(rows[i].stops);
    final startsBlock =
        i > 0 && p != null && !gluedByLegs.contains(rows[i].key);
    if (startsBlock && exit != null) total += straightLineMetres(exit, p);
    if (p != null) exit = p;
  }
  return total;
}

// ── Cost tables on a line and a plane ────────────────────────────────────────

/// A block on a line, in metres: entered at the first, left at the second.
typedef LineBlock = (int, int);

LineBlock at(int x) => (x, x);
LineBlock leg(int from, int to) => (from, to);

/// A day on a line: from [start] (null: free to leave) through [blocks] to
/// [end] (null: free to reach).
PathCosts lineCosts({
  required int? start,
  required List<LineBlock> blocks,
  int? end,
}) =>
    PathCosts.of<int>(
      start: start,
      blocks: blocks,
      end: end,
      metres: (a, b) => (a - b).abs(),
    );

/// A point on a plane, in metres.
typedef Pt = (int, int);

int planeMetres(Pt a, Pt b) {
  final dx = (a.$1 - b.$1).toDouble(), dy = (a.$2 - b.$2).toDouble();
  return math.sqrt(dx * dx + dy * dy).round();
}

double planeExact(Pt a, Pt b) {
  final dx = (a.$1 - b.$1).toDouble(), dy = (a.$2 - b.$2).toDouble();
  return math.sqrt(dx * dx + dy * dy);
}

enum EndKind { free, kept, roundTrip }

/// A day on a plane: a start (or none), blocks (stops, or legs entered at one
/// point and left at another) and an end.
class PlaneDay {
  const PlaneDay(this.start, this.blocks, this.end);

  final Pt? start;
  final List<(Pt, Pt)> blocks;
  final Pt? end;

  PathCosts get costs => PathCosts.of<Pt>(
      start: start, blocks: blocks, end: end, metres: planeMetres);

  /// The same day with its blocks in the order of [path]'s movable nodes.
  PlaneDay reordered(List<int> path) => PlaneDay(
        start,
        [for (final v in path.sublist(1, path.length - 1)) blocks[v - 1]],
        end,
      );

  /// The points [path] visits, in order: the start, each block's entry and
  /// exit, the end — what a crossing is looked for in.
  List<Pt> pointsOf(List<int> path) => [
        if (start != null) start!,
        for (final v in path.sublist(1, path.length - 1)) ...[
          blocks[v - 1].$1,
          if (blocks[v - 1].$2 != blocks[v - 1].$1) blocks[v - 1].$2,
        ],
        if (end != null) end!,
      ];
}

/// A random day of [count] blocks: spread over 20 km, or in three clusters of
/// 300 m; [legPercent] of the blocks legs up to 3 km long; [samePointPercent]
/// of them on a point already used; the end free, kept somewhere, or back at
/// the start.
PlaneDay randomDay(
  int seed,
  int count, {
  bool clustered = false,
  int legPercent = 0,
  EndKind end = EndKind.free,
  bool startWithoutPoint = false,
  int samePointPercent = 0,
}) {
  final rng = XorShift32(seed);
  final centres = [
    for (var i = 0; i < 3; i++) (rng.nextInt(20000), rng.nextInt(20000)),
  ];
  Pt point() {
    if (!clustered) return (rng.nextInt(20000), rng.nextInt(20000));
    final c = centres[rng.nextInt(3)];
    return (c.$1 + rng.nextInt(301) - 150, c.$2 + rng.nextInt(301) - 150);
  }

  final start = point();
  final used = <Pt>[start];
  final blocks = <(Pt, Pt)>[];
  for (var i = 0; i < count; i++) {
    final entry = used.isNotEmpty && rng.nextInt(100) < samePointPercent
        ? used[rng.nextInt(used.length)]
        : point();
    final exit = rng.nextInt(100) < legPercent
        ? (entry.$1 + rng.nextInt(6001) - 3000,
            entry.$2 + rng.nextInt(6001) - 3000)
        : entry;
    used.add(entry);
    blocks.add((entry, exit));
  }
  return PlaneDay(
    startWithoutPoint ? null : start,
    blocks,
    switch (end) {
      EndKind.free => null,
      EndKind.kept => point(),
      EndKind.roundTrip => start,
    },
  );
}

/// Shuffles [list] in place, from [rng].
void shuffleWith<T>(List<T> list, XorShift32 rng) {
  for (var i = list.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final t = list[i];
    list[i] = list[j];
    list[j] = t;
  }
}

// ── Oracles ──────────────────────────────────────────────────────────────────

/// Pairs of movable blocks visited against the input order.
int inversions(List<int> path) {
  final q = path.sublist(1, path.length - 1);
  var count = 0;
  for (var i = 0; i < q.length; i++) {
    for (var j = i + 1; j < q.length; j++) {
      if (q[i] > q[j]) count++;
    }
  }
  return count;
}

/// Every order of the movable blocks: the shortest, then among those the one
/// with the fewest inversions — what the exact search promises.
({int length, int inversions}) bruteForce(PathCosts d) {
  final m = d.m;
  var bestLength = -1, bestInversions = 0;
  final used = List<bool>.filled(m + 1, false);
  void visit(int here, int depth, int length, int inv) {
    if (depth == m) {
      final total = length + d(here, m + 1);
      if (bestLength < 0 ||
          total < bestLength ||
          (total == bestLength && inv < bestInversions)) {
        bestLength = total;
        bestInversions = inv;
      }
      return;
    }
    for (var v = 1; v <= m; v++) {
      if (used[v]) continue;
      var above = 0;
      for (var u = v + 1; u <= m; u++) {
        if (used[u]) above++;
      }
      used[v] = true;
      visit(v, depth + 1, length + d(here, v), inv + above);
      used[v] = false;
    }
  }

  visit(0, 0, 0, 0);
  return (length: bestLength, inversions: bestInversions);
}

/// Every Or-opt, 2-opt and swap there is on a path of [m] movable blocks, by
/// the definitions: a run of any length to every position it is not already
/// in; a section reversed; two blocks swapped.
Iterable<(MoveKind, int, int, int)> everyMove(int m) sync* {
  for (var a = 1; a <= m; a++) {
    for (var b = a; b <= m; b++) {
      if (b - a + 1 >= m) continue;
      for (var t = 0; t <= m; t++) {
        if (t >= a - 1 && t <= b) continue;
        yield (MoveKind.orOpt, a, b, t);
      }
    }
  }
  for (var i = 1; i < m; i++) {
    for (var j = i + 1; j <= m; j++) {
      yield (MoveKind.twoOpt, i, j, -1);
    }
  }
  for (var a = 1; a < m; a++) {
    for (var b = a + 1; b <= m; b++) {
      yield (MoveKind.swap, a, b, -1);
    }
  }
}

/// A move done by hand from its description alone.
List<int> applyMove(List<int> p, MoveKind kind, int i, int j, int k) {
  switch (kind) {
    case MoveKind.orOpt:
      final run = p.sublist(i, j + 1);
      final rest = [...p.sublist(0, i), ...p.sublist(j + 1)];
      final at = rest.indexOf(p[k]) + 1; // right after what was p[k]
      return [...rest.sublist(0, at), ...run, ...rest.sublist(at)];
    case MoveKind.twoOpt:
      return [
        ...p.sublist(0, i),
        ...p.sublist(i, j + 1).reversed,
        ...p.sublist(j + 1),
      ];
    case MoveKind.swap:
      final q = [...p];
      q[i] = p[j];
      q[j] = p[i];
      return q;
  }
}

int _orientation(Pt a, Pt b, Pt c) {
  final v = (b.$1 - a.$1) * (c.$2 - a.$2) - (b.$2 - a.$2) * (c.$1 - a.$1);
  return v.sign;
}

/// The most a path through [points] would save, before rounding, by undoing
/// one of its crossings; 0 when it crosses nowhere.
double worstCrossingSaving(List<Pt> points) {
  var worst = 0.0;
  for (var i = 0; i + 1 < points.length; i++) {
    for (var j = i + 2; j + 1 < points.length; j++) {
      final a = points[i], b = points[i + 1], c = points[j], d = points[j + 1];
      final crosses = _orientation(a, b, c) * _orientation(a, b, d) < 0 &&
          _orientation(c, d, a) * _orientation(c, d, b) < 0;
      if (!crosses) continue;
      final saving = planeExact(a, b) +
          planeExact(c, d) -
          planeExact(a, c) -
          planeExact(b, d);
      if (saving > worst) worst = saving;
    }
  }
  return worst;
}
