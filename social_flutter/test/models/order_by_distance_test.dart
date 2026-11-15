// test/models/order_by_distance_test.dart — Order by distance on whole trips,
// as the app calls it: what it reads (a stop's own coordinates, never
// Google's), what it moves (whole tracks, glued where they must stay
// together), when it suggests nothing, and the rules every answer keeps —
// measured again from the stops themselves. The solver on its own is
// order_by_distance_solver_test.dart; the same answer everywhere,
// order_by_distance_golden_test.dart.
//
// Points sit on the equator, where 0.01° of longitude is about 1.1 km, so a
// fixture's lengths can be read off its longitudes.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

import '../support/order_by_distance_fixtures.dart';

List<String>? _keys(DistanceOrderChoices c, OrderChoice choice) =>
    c.resultFor(choice)?.rowKeys;

/// Random trips with segments, tracks nothing locates (the first one too,
/// sometimes) and alternatives, from fixed seeds.
final _randomTrips = [
  for (var i = 0; i < 24; i++)
    randomTrip(
      'random-$i',
      700 + i,
      5 + i % 16,
      legPercent: i % 3 == 0 ? 0 : 35,
      unmeasuredPercent: i % 4 == 0 ? 0 : 30,
      firstUnmeasured: i % 5 == 1,
      alternativesPercent: i % 2 == 0 ? 0 : 30,
      clustered: i % 6 == 2,
    ),
];

void main() {
  group('what moves', () {
    test('a scrambled line comes out in order; the start stays first',
        () async {
      final c = await choicesFor([
        trackAt('S', 0.00),
        trackAt('A', 0.03),
        trackAt('B', 0.01),
        trackAt('C', 0.04),
        trackAt('D', 0.02),
        trackAt('E', 0.05),
      ]);
      expect(_keys(c, keepAll), ['S', 'B', 'D', 'A', 'C', 'E']);
      // S and E are the line's two ends anyway: where the trip starts or ends
      // changes nothing.
      expect(c.startMatters, isFalse);
      expect(c.endMatters, isFalse);
      expect(c.legsMatter, isFalse);
      expect(c.reason, isNull);
    });

    test('the start stays first only when asked; free, the trip starts where '
        'the path is shortest', () async {
      final c = await choicesFor([
        trackAt('S', 0.02),
        trackAt('A', 0.00),
        trackAt('B', 0.01),
        trackAt('C', 0.03),
        trackAt('D', 0.04),
      ]);
      // Kept first, S is already left the shortest way.
      expect(c.resultFor(keepAll), isNull);
      expect(c.resultFor(freeEnd), isNull);
      final order = c.resultFor(freeStart)!;
      expect(order.rowKeys, ['A', 'B', 'S', 'C', 'D']);
      expect(order.wasNumber, {'S': 1});
      expect(c.startMatters, isTrue);
      // D is the far end whichever way the trip starts.
      expect(_keys(c, freeBoth), order.rowKeys);
      expect(c.endMatters, isFalse);
    });

    test('the end stays last only when asked; free, it ends where it is '
        'shortest', () async {
      final c = await choicesFor([
        trackAt('S', 0.00),
        trackAt('A', 0.05),
        trackAt('B', 0.01),
        trackAt('C', 0.02),
      ]);
      expect(_keys(c, keepAll), ['S', 'B', 'A', 'C']);
      expect(_keys(c, freeEnd), ['S', 'B', 'C', 'A']);
      expect(c.endMatters, isTrue);
    });

    test('alternatives keep their order and their track; a track is measured '
        'from its first alternative with saved coordinates', () async {
      final c = await choicesFor([
        trackAt('S', 0.00),
        // Measured at y (0.03): x has no coordinates.
        orderTrack('T', [orderStop('x', 'T'), orderStop('y', 'T', lng: 0.03)]),
        trackAt('B', 0.01),
        trackAt('C', 0.02),
      ]);
      final order = c.resultFor(freeEnd)!;
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
      final c = await choicesFor([
        trackAt('S', 0.00),
        trackAt('U', null),
        trackAt('A', 0.03),
        trackAt('B', 0.01),
        orderTrack('V', [orderStop('V', 'V', googlePlaceId: 'ChIJ-place')]),
        trackAt('C', 0.02),
      ]);
      final order = c.resultFor(freeEnd)!;
      expect(order.rowKeys, ['S', 'U', 'B', 'V', 'C', 'A']);
      expect(order.unmeasured, 2);
    });

    test('a first track nothing locates is still the start, and leaving it '
        'costs nothing; equally short orders keep the input order', () async {
      final c = await choicesFor([
        trackAt('U', null),
        trackAt('A', 0.03),
        trackAt('B', 0.01),
        trackAt('C', 0.02),
      ]);
      // A·C·B and B·C·A are equally short; A·C·B inverts less of A·B·C.
      expect(_keys(c, freeEnd), ['U', 'A', 'C', 'B']);
      expect(c.resultFor(freeEnd)!.unmeasured, 0);
      // Nothing says where else U would go: it stays first, whatever the
      // answer, and the start is never asked about.
      expect(_keys(c, freeBoth), ['U', 'A', 'C', 'B']);
      expect(c.startMatters, isFalse);
    });

    test('Google places and Google Maps links are never measured', () async {
      final c = await choicesFor([
        trackAt('S', 0.00),
        trackAt('A', 0.02),
        trackAt('B', 0.01),
        // A Google place, even holding coordinates no server would store.
        orderTrack('G', [
          orderStop('G', 'G', lng: 0.005, googlePlaceId: 'ChIJ-place'),
        ]),
        // A link whose own text carries coordinates.
        orderTrack('L', [
          orderStop('L', 'L',
              mapUrl: 'https://www.google.com/maps/@0.0,0.004,15z'),
        ]),
      ]);
      expect(c.located, 3);
      // Both travel with B, the track before them: G and L hold their order.
      expect(_keys(c, freeEnd), ['S', 'B', 'G', 'L', 'A']);
      expect(c.resultFor(freeEnd)!.unmeasured, 2);
    });
  });

  group('transit segments', () {
    // X→Y is a leg; X is far, Y and Z near the start.
    final tracks = [
      trackAt('S', 0.00),
      trackAt('X', 0.05),
      trackAt('Y', 0.01),
      trackAt('Z', 0.02),
    ];
    final legs = [orderSegment('leg', 'X', 'Y')];

    test('kept, linked tracks move as one block, in their direction', () async {
      final c = await choicesFor(tracks, segments: legs);
      final kept = c.resultFor(freeEnd)!;
      expect(kept.rowKeys, ['S', 'Z', 'X', 'Y']);
      expect(kept.brokenLegs, isEmpty);
    });

    test('deleted, the order is shorter and names the segment it breaks',
        () async {
      final c = await choicesFor(tracks, segments: legs);
      final broken = c.resultFor(freeEndNoLegs)!;
      expect(broken.rowKeys, ['S', 'Y', 'Z', 'X']);
      expect(broken.brokenLegs.map((s) => s.id), ['leg']);
      expect(c.legsMatter, isTrue);
    });

    test('a segment already broken by the arrangement glues nothing', () async {
      // Y→X runs backwards in this order: it is an orphan, not a link.
      final c = await choicesFor(tracks,
          segments: [orderSegment('back', 'Y', 'X')]);
      expect(c.legsLive, isFalse);
      expect(c.legsMatter, isFalse);
      expect(_keys(c, keepAll), _keys(c, keepAll.copyWith(keepLegs: false)));
    });

    test(
        'Given start 0, a leg from 0 to 10 km, S1 at 10.1 km and S2 at 100 m, '
        'When the end is free, Then S2, the leg, S1 — 300 m, the leg run from '
        'its exit', () async {
      final c = await choicesFor([
        trackAtMetres('start', 0),
        trackAtMetres('L1', 0),
        trackAtMetres('L2', 10000),
        trackAtMetres('S1', 10100),
        trackAtMetres('S2', 100),
      ], segments: [
        orderSegment('leg', 'L1', 'L2'),
      ]);
      final order = c.resultFor(freeEnd)!;
      expect(order.rowKeys, ['start', 'S2', 'L1', 'L2', 'S1']);
      expect(order.lengthMetres, 300);
    });
  });

  group('when there is nothing to suggest', () {
    test('a gain under 200 m is no suggestion', () async {
      final c = await choicesFor([
        trackAt('S', 0.0),
        trackAt('A', 0.0015),
        trackAt('B', 0.001),
        trackAt('C', 0.002),
      ]);
      expect(c.hasSuggestion, isFalse);
      expect(c.reason, NoOrderReason.alreadyInOrder);
    });

    test('a gain under 3% is no suggestion, however many metres', () async {
      final c = await choicesFor([
        trackAt('S', 0.0),
        trackAt('A', 1.0),
        trackAt('B', 0.99),
        trackAt('C', 2.0),
      ]);
      expect(c.hasSuggestion, isFalse);
    });

    test('a trip already in order says so', () async {
      final c = await choicesFor([
        trackAt('S', 0.00),
        trackAt('A', 0.01),
        trackAt('B', 0.02),
        trackAt('C', 0.03),
      ]);
      expect(c.reason, NoOrderReason.alreadyInOrder);
    });

    test('fewer than three located tracks is too few, wherever they are',
        () async {
      final c = await choicesFor([
        trackAt('S', 0.00),
        trackAt('A', 0.03),
        trackAt('B', null),
        trackAt('C', null),
      ]);
      expect(c.reason, NoOrderReason.tooFewLocated);
      expect(c.located, 2);
      expect(c.total, 4);

      // Behind a first track nothing locates: between A and B, either order
      // is as short.
      final behind = await choicesFor([
        trackAt('U', null),
        trackAt('A', 0.03),
        trackAt('B', 0.01),
        trackAt('C', null),
      ]);
      expect(behind.reason, NoOrderReason.tooFewLocated);
    });

    test('two tracks have nothing to move', () async {
      final c = await choicesFor([trackAt('S', 0.00), trackAt('A', 0.03)]);
      expect(c.hasSuggestion, isFalse);
    });
  });

  test('"moved" counts the tracks to move by hand, not every one pushed down',
      () async {
    final c = await choicesFor([
      trackAt('S', 0.00),
      trackAt('A', 0.02),
      trackAt('B', 0.03),
      trackAt('C', 0.04),
      trackAt('D', 0.01),
    ]);
    final order = c.resultFor(freeEnd)!;
    expect(order.rowKeys, ['S', 'D', 'A', 'B', 'C']);
    expect(order.moved, 1);
    expect(order.wasNumber, {'D': 5});
  });

  test('longestIncreasingRun keeps one longest run in order', () {
    expect(longestIncreasingRun([0, 4, 1, 2, 3]), {0, 2, 3, 4});
    expect(longestIncreasingRun([0, 1, 2]), {0, 1, 2});
    expect(longestIncreasingRun(<int>[]), isEmpty);
  });

  group('the whole trip', () {
    test(
        'Given 14 tracks with the start and the end kept, When worked out, '
        'Then the 12 tracks between come out exactly as the exact search '
        'orders them — "up to 12" includes 12', () async {
      final tracks = scatteredTracks(14, seed: 1414);
      final points = [for (final t in tracks) pointOfTrack(t.stops)!];
      final d = PathCosts.of<LatLng>(
        start: points.first,
        blocks: [for (final p in points.sublist(1, 13)) (p, p)],
        end: points.last,
        metres: straightLineMetres,
      );
      expect(d.m, 12);
      final exact = exactOrder(d);
      final c = await choicesFor(tracks);
      expect(c.resultFor(keepAll)!.rowKeys, [for (final v in exact) 't$v']);
      expect(c.resultFor(keepAll)!.lengthMetres, d.lengthOf(exact));
    });

    test('30 scattered tracks: the same order every run, shorter than the '
        'input and than nearest neighbour alone', () async {
      final tracks = scatteredTracks(30);
      final first = await choicesFor(tracks);
      final again = await choicesFor(tracks);
      final order = first.resultFor(freeEnd)!;
      expect(order.rowKeys, again.resultFor(freeEnd)!.rowKeys);
      expect(order.lengthMetres, lessThan(order.previousLengthMetres));
      final points = [for (final t in tracks) pointOfTrack(t.stops)!];
      final d = PathCosts.of<LatLng>(
        start: points.first,
        blocks: [for (final p in points.skip(1)) (p, p)],
        end: null,
        metres: straightLineMetres,
      );
      expect(
          d.lengthOf(nearestNeighbourOrder(d)), greaterThan(order.lengthMetres));
      expect(order.rowKeys, _pinnedScatteredOrder);
      // A free start too: the same order every run, never longer than now.
      final free = first.resultFor(freeBoth)!;
      expect(free.rowKeys, again.resultFor(freeBoth)!.rowKeys);
      expect(free.lengthMetres, lessThan(free.previousLengthMetres));
    });

    test('cancelled at a pause, the work stops and answers nothing', () async {
      expect(
        await orderByDistanceChoices(
            TripArrangement.of(scatteredTracks(30)), const [],
            isCancelled: () => true),
        isNull,
      );
    });

    // Item 22.
    test(
        'Given random trips, When every choice is worked out, Then each answer '
        'holds every track once with its stops, keeps a kept start first and '
        'a kept end last, and never splits or turns round a kept segment',
        () async {
      var checked = 0, legsChecked = 0;
      for (final day in _randomTrips) {
        final c = (await orderByDistanceChoices(day.arrangement, day.segments))!;
        final original = day.arrangement.rows;
        for (final choice in OrderChoice.all) {
          final order = c.resultFor(choice);
          if (order == null) continue;
          final rows = order.arrangement.rows;
          final why = '${day.name} ${choiceCode(choice)}';
          expect(rows.map((r) => r.key).toSet(),
              original.map((r) => r.key).toSet(),
              reason: why);
          expect(rows.length, original.length, reason: why);
          for (final r in rows) {
            final before = original.firstWhere((o) => o.key == r.key);
            expect(r.stops.map((s) => s.id), before.stops.map((s) => s.id),
                reason: why);
          }
          if (choice.keepStart) {
            expect(rows.first.key, original.first.key, reason: why);
          }
          if (choice.keepEnd) {
            expect(rows.last.key, original.last.key, reason: why);
          }
          if (choice.keepLegs) {
            int rowOf(String stopId) =>
                rows.indexWhere((r) => r.stops.any((x) => x.id == stopId));
            for (final s in day.segments) {
              expect(rowOf(s.toStopId), rowOf(s.fromStopId) + 1,
                  reason: '$why ${s.id}');
              legsChecked++;
            }
          }
          checked++;
        }
      }
      expect(checked, greaterThan(60), reason: 'answers checked');
      expect(legsChecked, greaterThan(20), reason: 'kept segments checked');
    });

    // Item 23.
    test(
        'Given random trips, When every choice is worked out, Then the length '
        'each answer reports, before and after, is the length measured again '
        'from its stops', () async {
      var checked = 0;
      for (final day in _randomTrips) {
        final c = (await orderByDistanceChoices(day.arrangement, day.segments))!;
        for (final choice in OrderChoice.all) {
          final order = c.resultFor(choice);
          if (order == null) continue;
          final glued =
              choice.keepLegs ? day.gluedByLegs : const <String>{};
          final why = '${day.name} ${choiceCode(choice)}';
          expect(order.lengthMetres,
              measuredLength(order.arrangement.rows, gluedByLegs: glued),
              reason: why);
          expect(order.previousLengthMetres,
              measuredLength(day.arrangement.rows, gluedByLegs: glued),
              reason: why);
          checked++;
        }
      }
      expect(checked, greaterThan(60), reason: 'answers checked');
    });

    // Item 35.
    test(
        'Given random trips with tracks nothing locates, When every choice is '
        'worked out, Then nothing throws, a first one stays first, and every '
        'other stays right after the track before it', () async {
      var checked = 0;
      for (final day in _randomTrips) {
        final c = (await orderByDistanceChoices(day.arrangement, day.segments))!;
        final original = day.arrangement.rows;
        final unmeasured = day.unmeasured;
        for (final choice in OrderChoice.all) {
          final order = c.resultFor(choice);
          if (order == null) continue;
          final rows = order.arrangement.rows;
          final why = '${day.name} ${choiceCode(choice)}';
          for (var i = 0; i < original.length; i++) {
            if (!unmeasured.contains(original[i].key)) continue;
            final at = rows.indexWhere((r) => r.key == original[i].key);
            if (i == 0) {
              expect(at, 0, reason: why);
            } else {
              expect(rows[at - 1].key, original[i - 1].key, reason: why);
            }
            checked++;
          }
        }
      }
      expect(checked, greaterThan(60), reason: 'unlocated tracks checked');
    });

    // Item 31.
    test(
        'Given tracks about 20,000 km apart, When worked out, Then every '
        'length reported is the one measured again, to the metre', () async {
      final tracks = [
        trackAt('A', 0, lat: 0),
        trackAt('B', 179.5, lat: 0.5),
        trackAt('C', -1, lat: -0.5),
        trackAt('D', -179.9, lat: 1),
        trackAt('E', 90, lat: 45),
        trackAt('F', -90, lat: -45),
        trackAt('G', 2, lat: 0.2),
      ];
      final c = await choicesFor(tracks);
      expect(c.hasSuggestion, isTrue);
      for (final choice in OrderChoice.all) {
        final order = c.resultFor(choice);
        if (order == null) continue;
        expect(order.lengthMetres, measuredLength(order.arrangement.rows),
            reason: choiceCode(choice));
        expect(order.previousLengthMetres,
            measuredLength(TripArrangement.of(tracks).rows));
        expect(order.previousLengthMetres, greaterThan(60000000));
      }
    });
  });

  // Item 32.
  group('straightLineMetres', () {
    test('Given the same point twice, Then 0 m', () {
      expect(straightLineMetres(const LatLng(50, 4), const LatLng(50, 4)), 0);
    });

    test('Given (50.000, 4.000) and (50.001, 4.000), Then 111 m', () {
      expect(
          straightLineMetres(const LatLng(50.000, 4.000),
              const LatLng(50.001, 4.000)),
          111);
    });

    test('Given two points, Then A → B is B → A, in whole metres', () {
      final rng = XorShift32(32);
      double unit() => (rng.nextInt(20001) - 10000) / 10000;
      for (var i = 0; i < 200; i++) {
        final a = LatLng(unit() * 80, unit() * 180);
        final b = LatLng(unit() * 80, unit() * 180);
        final ab = straightLineMetres(a, b);
        expect(ab, straightLineMetres(b, a));
        expect(ab, isA<int>());
        expect(ab, greaterThanOrEqualTo(0));
      }
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
