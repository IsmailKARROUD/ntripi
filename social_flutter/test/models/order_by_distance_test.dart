// test/models/order_by_distance_test.dart — Order by distance, as plain
// function calls: what it reads (a stop's own coordinates, never Google's),
// what it moves (whole tracks, glued where they must stay together), and the
// two solvers' promises — exact up to 12 blocks, never longer than the input,
// the user's order on a tie, and the same answer on every run.
//
// Points sit on the equator, where 0.01° of longitude is about 1.1 km, so a
// fixture's lengths can be read off its longitudes.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

Stop _stop(
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

/// A track [id] holding one stop of the same name at longitude [lng] (none
/// when null).
Track _at(String id, double? lng) =>
    Track(id: id, itineraryId: 'itin-1', rank: id, stops: [_stop(id, id, lng: lng)]);

Track _track(String id, List<Stop> stops) =>
    Track(id: id, itineraryId: 'itin-1', rank: id, stops: stops);

TransitSegment _segment(String id, String from, String to) => TransitSegment(
      id: id,
      itineraryId: 'itin-1',
      fromStopId: from,
      toStopId: to,
      totalDurationMin: 10,
      totalCost: 0,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<DistanceOrderChoices> _choices(
  List<Track> tracks, {
  List<TransitSegment> segments = const [],
}) async =>
    (await orderByDistanceChoices(TripArrangement.of(tracks), segments))!;

const _keepAll = OrderChoice(keepEnd: true, keepLegs: true);
const _freeEnd = OrderChoice(keepEnd: false, keepLegs: true);
const _freeAll = OrderChoice(keepEnd: false, keepLegs: false);

List<String>? _keys(DistanceOrderChoices c, OrderChoice choice) =>
    c.resultFor(choice)?.rowKeys;

/// A random asymmetric table of metres for m movable blocks, with a fixed or
/// a virtual end (a column of zeros into node m+1).
PathCosts _randomCosts(math.Random rng, int m, {required bool fixedEnd}) {
  final n = m + 2;
  return PathCosts.fromRows([
    for (var u = 0; u < n; u++)
      [
        for (var v = 0; v < n; v++)
          if (u == v || v == 0 || u == n - 1 || (v == n - 1 && !fixedEnd))
            0
          else
            rng.nextInt(20000),
      ],
  ]);
}

/// The shortest length over every order of the movable blocks.
int _bruteForce(PathCosts d) {
  var best = -1;
  void visit(List<int> path, List<bool> used) {
    if (path.length == d.m + 1) {
      final length = d.lengthOf([...path, d.m + 1]);
      if (best < 0 || length < best) best = length;
      return;
    }
    for (var v = 1; v <= d.m; v++) {
      if (used[v]) continue;
      used[v] = true;
      visit([...path, v], used);
      used[v] = false;
    }
  }

  visit([0], List<bool>.filled(d.m + 1, false));
  return best;
}

/// [count] tracks scattered over about 10 km, from xorshift — not dart:math's
/// Random, whose stream may differ on the web, where a pinned order must hold.
List<Track> _scattered(int count) {
  final rng = XorShift32(99);
  double coordinate() => rng.nextInt(9000) / 100000;
  return [
    for (var i = 0; i < count; i++)
      Track(
        id: 't$i',
        itineraryId: 'itin-1',
        rank: 't$i',
        stops: [_stop('t$i', 't$i', lat: coordinate(), lng: coordinate())],
      ),
  ];
}

/// The free-end costs of one-stop [tracks]: the first is the start, the rest
/// movable in order, then the virtual end.
PathCosts _freeEndCosts(List<Track> tracks) {
  final points = [
    for (final t in tracks) LatLng(t.stops.first.lat!, t.stops.first.lng!),
  ];
  final n = points.length + 1;
  return PathCosts.fromRows([
    for (var u = 0; u < n; u++)
      [
        for (var v = 0; v < n; v++)
          if (u == v || v == 0 || u == n - 1 || v == n - 1)
            0
          else
            const Haversine().distance(points[u], points[v]).round(),
      ],
  ]);
}

void main() {
  group('what moves', () {
    test('a scrambled line comes out in order; the start stays first',
        () async {
      final c = await _choices([
        _at('S', 0.00),
        _at('A', 0.03),
        _at('B', 0.01),
        _at('C', 0.04),
        _at('D', 0.02),
        _at('E', 0.05),
      ]);
      expect(_keys(c, _keepAll), ['S', 'B', 'D', 'A', 'C', 'E']);
      // E is the far end anyway: where the trip ends changes nothing.
      expect(c.endMatters, isFalse);
      expect(c.legsMatter, isFalse);
      expect(c.reason, isNull);
    });

    test('the end stays last only when asked; free, it ends where it is '
        'shortest', () async {
      final c = await _choices([
        _at('S', 0.00),
        _at('A', 0.05),
        _at('B', 0.01),
        _at('C', 0.02),
      ]);
      expect(_keys(c, _keepAll), ['S', 'B', 'A', 'C']);
      expect(_keys(c, _freeEnd), ['S', 'B', 'C', 'A']);
      expect(c.endMatters, isTrue);
    });

    test('alternatives keep their order and their track; a track is measured '
        'from its first alternative with saved coordinates', () async {
      final c = await _choices([
        _at('S', 0.00),
        // Measured at y (0.03): x has no coordinates.
        _track('T', [_stop('x', 'T'), _stop('y', 'T', lng: 0.03)]),
        _at('B', 0.01),
        _at('C', 0.02),
      ]);
      final order = c.resultFor(_freeEnd)!;
      expect(order.rowKeys, ['S', 'B', 'C', 'T']);
      expect(
          order.arrangement.rows.last.stops.map((s) => s.id), ['x', 'y']);
      expect(order.arrangement.toLayoutJson().last, {
        'track_id': 'T',
        'stop_ids': ['x', 'y'],
      });
    });

    test('a track without saved coordinates stays after the track before it',
        () async {
      final c = await _choices([
        _at('S', 0.00),
        _at('U', null),
        _at('A', 0.03),
        _at('B', 0.01),
        _track('V', [_stop('V', 'V', googlePlaceId: 'ChIJ-place')]),
        _at('C', 0.02),
      ]);
      final order = c.resultFor(_freeEnd)!;
      expect(order.rowKeys, ['S', 'U', 'B', 'V', 'C', 'A']);
      expect(order.unmeasured, 2);
    });

    test('a first track nothing locates is still the start, and leaving it '
        'costs nothing; equally short orders keep the input order', () async {
      final c = await _choices([
        _at('U', null),
        _at('A', 0.03),
        _at('B', 0.01),
        _at('C', 0.02),
      ]);
      // A·C·B and B·C·A are equally short; A·C·B inverts less of A·B·C.
      expect(_keys(c, _freeEnd), ['U', 'A', 'C', 'B']);
      expect(c.resultFor(_freeEnd)!.unmeasured, 0);
    });

    test('Google places and Google Maps links are never measured', () async {
      final c = await _choices([
        _at('S', 0.00),
        _at('A', 0.02),
        _at('B', 0.01),
        // A Google place, even holding coordinates no server would store.
        _track('G', [
          _stop('G', 'G', lng: 0.005, googlePlaceId: 'ChIJ-place'),
        ]),
        // A link whose own text carries coordinates.
        _track('L', [
          _stop('L', 'L',
              mapUrl: 'https://www.google.com/maps/@0.0,0.004,15z'),
        ]),
      ]);
      expect(c.located, 3);
      // Both travel with B, the track before them: G and L hold their order.
      expect(_keys(c, _freeEnd), ['S', 'B', 'G', 'L', 'A']);
      expect(c.resultFor(_freeEnd)!.unmeasured, 2);
    });
  });

  group('transit segments', () {
    // X→Y is a leg; X is far, Y and Z near the start.
    final tracks = [
      _at('S', 0.00),
      _at('X', 0.05),
      _at('Y', 0.01),
      _at('Z', 0.02),
    ];
    final legs = [_segment('leg', 'X', 'Y')];

    test('kept, linked tracks move as one block, in their direction', () async {
      final c = await _choices(tracks, segments: legs);
      final kept = c.resultFor(_freeEnd)!;
      expect(kept.rowKeys, ['S', 'Z', 'X', 'Y']);
      expect(kept.brokenLegs, isEmpty);
    });

    test('deleted, the order is shorter and names the segment it breaks',
        () async {
      final c = await _choices(tracks, segments: legs);
      final broken = c.resultFor(_freeAll)!;
      expect(broken.rowKeys, ['S', 'Y', 'Z', 'X']);
      expect(broken.brokenLegs.map((s) => s.id), ['leg']);
      expect(c.legsMatter, isTrue);
    });

    test('a segment already broken by the arrangement glues nothing', () async {
      // Y→X runs backwards in this order: it is an orphan, not a link.
      final c = await _choices(tracks, segments: [_segment('back', 'Y', 'X')]);
      expect(c.legsLive, isFalse);
      expect(c.legsMatter, isFalse);
      expect(_keys(c, _keepAll),
          _keys(c, const OrderChoice(keepEnd: true, keepLegs: false)));
    });
  });

  group('when there is nothing to suggest', () {
    test('a gain under 200 m is no suggestion', () async {
      final c = await _choices([
        _at('S', 0.0),
        _at('A', 0.0015),
        _at('B', 0.001),
        _at('C', 0.002),
      ]);
      expect(c.hasSuggestion, isFalse);
      expect(c.reason, NoOrderReason.alreadyInOrder);
    });

    test('a gain under 3% is no suggestion, however many metres', () async {
      final c = await _choices([
        _at('S', 0.0),
        _at('A', 1.0),
        _at('B', 0.99),
        _at('C', 2.0),
      ]);
      expect(c.hasSuggestion, isFalse);
    });

    test('a trip already in order says so', () async {
      final c = await _choices([
        _at('S', 0.00),
        _at('A', 0.01),
        _at('B', 0.02),
        _at('C', 0.03),
      ]);
      expect(c.reason, NoOrderReason.alreadyInOrder);
    });

    test('fewer than two located tracks after the first is too few', () async {
      final c = await _choices([
        _at('S', 0.00),
        _at('A', 0.03),
        _at('B', null),
        _at('C', null),
      ]);
      expect(c.reason, NoOrderReason.tooFewLocated);
      expect(c.located, 2);
      expect(c.total, 4);
    });

    test('two tracks have nothing to move', () async {
      final c = await _choices([_at('S', 0.00), _at('A', 0.03)]);
      expect(c.hasSuggestion, isFalse);
    });
  });

  test('"moved" counts the tracks to move by hand, not every one pushed down',
      () async {
    final c = await _choices([
      _at('S', 0.00),
      _at('A', 0.02),
      _at('B', 0.03),
      _at('C', 0.04),
      _at('D', 0.01),
    ]);
    final order = c.resultFor(_freeEnd)!;
    expect(order.rowKeys, ['S', 'D', 'A', 'B', 'C']);
    expect(order.moved, 1);
    expect(order.wasNumber, {'D': 5});
  });

  test('longestIncreasingRun keeps one longest run in order', () {
    expect(longestIncreasingRun([0, 4, 1, 2, 3]), {0, 2, 3, 4});
    expect(longestIncreasingRun([0, 1, 2]), {0, 1, 2});
    expect(longestIncreasingRun(<int>[]), isEmpty);
  });

  group('Held-Karp', () {
    test('matches brute force, with a fixed and with a virtual end', () {
      final rng = math.Random(42);
      for (var trial = 0; trial < 60; trial++) {
        final m = 2 + trial % 7;
        final d = _randomCosts(rng, m, fixedEnd: trial.isEven);
        expect(d.lengthOf(exactOrder(d)), _bruteForce(d),
            reason: 'trial $trial, m=$m');
      }
    });

    test('score ~/ 256 is the length in metres, first and last steps included',
        () {
      final rng = math.Random(3);
      for (var trial = 0; trial < 20; trial++) {
        final d = _randomCosts(rng, 3 + trial % 9, fixedEnd: trial.isOdd);
        final (:order, :score) = exactOrderWithScore(d);
        expect(score ~/ 256, d.lengthOf(order));
      }
    });

    test('on equal lengths the input order wins', () {
      final m = 9;
      final d = PathCosts.fromRows([
        for (var u = 0; u < m + 2; u++)
          [for (var v = 0; v < m + 2; v++) u == v ? 0 : 1000],
      ]);
      expect(exactOrder(d), d.identity());
    });
  });

  group('local search', () {
    test('never longer than the input order, and the input wins a tie', () async {
      final rng = math.Random(11);
      for (var trial = 0; trial < 10; trial++) {
        final d = _randomCosts(rng, 13 + trial, fixedEnd: trial.isEven);
        final order = await localSearchOrder(d);
        expect(d.lengthOf(order), lessThanOrEqualTo(d.lengthOf(d.identity())));
        expect(order.toSet(), d.identity().toSet(), reason: 'a permutation');
      }
      final flat = PathCosts.fromRows([
        for (var u = 0; u < 17; u++)
          [for (var v = 0; v < 17; v++) u == v ? 0 : 500],
      ]);
      expect(await localSearchOrder(flat), flat.identity(),
          reason: 'plateau moves never change what is returned');
    });

    test('the 2-opt change matches the path recomputed', () {
      final rng = math.Random(5);
      for (var trial = 0; trial < 200; trial++) {
        final m = 3 + trial % 15;
        final d = _randomCosts(rng, m, fixedEnd: trial.isEven);
        final p = [0, ...([for (var i = 1; i <= m; i++) i]..shuffle(rng)), m + 1];
        final f = List<int>.filled(m + 2, 0), r = List<int>.filled(m + 2, 0);
        for (var k = 0; k <= m; k++) {
          f[k + 1] = f[k] + d(p[k], p[k + 1]);
          r[k + 1] = r[k] + d(p[k + 1], p[k]);
        }
        final i = 1 + rng.nextInt(m - 1);
        final j = i + 1 + rng.nextInt(m - i);
        final reversed = [
          ...p.sublist(0, i),
          ...p.sublist(i, j + 1).reversed,
          ...p.sublist(j + 1),
        ];
        expect(twoOptChange(d, p, i, j, f, r),
            d.lengthOf(reversed) - d.lengthOf(p),
            reason: 'trial $trial, m=$m, i=$i, j=$j');
      }
    });

    test('0 and 1 movable blocks give the input order back', () async {
      for (final m in [0, 1]) {
        final d = PathCosts.fromRows([
          for (var u = 0; u < m + 2; u++) [for (var v = 0; v < m + 2; v++) 7],
        ]);
        expect(exactOrder(d), d.identity());
        expect(await localSearchOrder(d), d.identity());
      }
    });

    test('30 scattered tracks: the same order every run, shorter than the '
        'input and than nearest neighbour alone', () async {
      final tracks = _scattered(30);
      final first = await _choices(tracks);
      final again = await _choices(tracks);
      final order = first.resultFor(_freeEnd)!;
      expect(order.rowKeys, again.resultFor(_freeEnd)!.rowKeys);
      expect(order.lengthMetres, lessThan(order.previousLengthMetres));
      final d = _freeEndCosts(tracks);
      expect(d.lengthOf(nearestNeighbourOrder(d)), greaterThan(order.lengthMetres));
      expect(order.rowKeys, _pinnedScatteredOrder);
    });

    test('40 tracks: every choice worked out within the budget', () async {
      final watch = Stopwatch()..start();
      final c = await _choices(_scattered(40));
      watch.stop();
      expect(c.hasSuggestion, isTrue);
      // Measured 285–362 ms here on the development Mac (2026-11-14, two
      // choices); release builds took 153 ms (AOT) and 174 ms (dart2js -O2,
      // Node 22). The budget is about ten times the VM's, so a slow machine
      // passes and an accidental O(m⁴) does not. The VM only: the browser
      // test runner compiles without release optimisation (5.5 s).
      expect(watch.elapsedMilliseconds, lessThan(3000));
    }, testOn: 'vm');

    test('cancelled at a pause, the work stops and answers nothing', () async {
      expect(
        await orderByDistanceChoices(
            TripArrangement.of(_scattered(30)), const [],
            isCancelled: () => true),
        isNull,
      );
    });
  });

  group('XorShift32', () {
    test('its first values are pinned, so every platform draws the same cuts',
        () {
      final rng = XorShift32(kOrderSeed);
      expect([for (var i = 0; i < 5; i++) rng.next()],
          [3336926330, 1697253807, 2816511904, 1955480042, 718842323]);
    });

    test('refuses a zero seed, whose state would stay 0 forever', () {
      expect(() => XorShift32(0), throwsA(isA<AssertionError>()));
    });
  });
}

/// What the 30-track fixture comes out as — pinned so a change to either
/// solver that moves the answer is a decision, not an accident.
const _pinnedScatteredOrder = [
  't0', 't2', 't3', 't16', 't28', 't24', 't7', 't8', 't22', 't5', 't12',
  't11', 't17', 't13', 't1', 't20', 't21', 't14', 't4', 't27', 't23', 't15',
  't29', 't19', 't18', 't9', 't10', 't25', 't26', 't6',
];
