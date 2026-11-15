// test/models/order_by_distance_solver_test.dart — the Order by distance
// solver on its own, held to the owner's specification of 2026-11-15: edge
// cases (A), the exact search up to 12 blocks (B), the local search above
// (C), its building blocks (D) and the rules every answer keeps (E).
//
// Days are whole metres on a line (`at`, `leg`) or a plane (`randomDay`),
// built through PathCosts.of — the builder the app uses — so a block is
// always entered at its first point and left at its last. Every expected
// order and length below is the owner's. The heavy batches run on the VM
// only; the golden file holds the web to the same answers.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';

import '../support/order_by_distance_fixtures.dart';

/// Where the blocks [path] visits sit on the line, in order.
List<int> _positions(List<LineBlock> blocks, List<int> path) =>
    [for (final v in path.sublist(1, path.length - 1)) blocks[v - 1].$1];

/// A double-bridge read off its result: the same blocks, the start and the
/// end in place, and the middle A B C D E turned into A D C B E with B, C and
/// D non-empty. Every block is a different number, so the longest shared
/// head is A and the longest shared tail is E.
void _expectDoubleBridge(List<int> before, List<int> after, String why) {
  expect(after.first, before.first, reason: why);
  expect(after.last, before.last, reason: why);
  expect(after.length, before.length, reason: why);
  final q = before.sublist(1, before.length - 1);
  final r = after.sublist(1, after.length - 1);
  expect(r.toSet(), q.toSet(), reason: why);
  var a = 0;
  while (a < q.length && q[a] == r[a]) {
    a++;
  }
  var e = 0;
  while (e < q.length - a && q[q.length - 1 - e] == r[r.length - 1 - e]) {
    e++;
  }
  final bcd = q.sublist(a, q.length - e), dcb = r.sublist(a, r.length - e);
  expect(bcd, isNotEmpty, reason: '$why: the order changed');
  final dLength = bcd.length - bcd.indexOf(dcb.first);
  final bLength = dcb.length - dcb.indexOf(bcd.first);
  final cLength = bcd.length - bLength - dLength;
  expect(bLength > 0 && cLength > 0 && dLength > 0, isTrue,
      reason: '$why: B $bLength, C $cLength, D $dLength');
  expect(
    dcb,
    [
      ...bcd.sublist(bLength + cLength),
      ...bcd.sublist(bLength, bLength + cLength),
      ...bcd.sublist(0, bLength),
    ],
    reason: why,
  );
}

typedef _Step = bool Function(PathCosts d, List<int> p, [MoveProbe? probe]);

void main() {
  group('A. Edge cases', () {
    test('Given 0 or 1 movable block, When any solver runs, Then the input '
        'comes back unchanged', () async {
      for (final start in [0, null]) {
        for (final end in [800, null]) {
          for (final blocks in [<LineBlock>[], [at(500)]]) {
            final d = lineCosts(start: start, blocks: blocks, end: end);
            expect(exactOrder(d), d.identity());
            expect(await localSearchOrder(d), d.identity());
            expect(await bestOrder(d), d.identity());
            expect(nearestNeighbourOrder(d), d.identity());
            expect(await improve(d, d.identity()), d.identity());
          }
        }
      }
    });

    test('Given start 0, A at 1000 and B at −1000, When the input is A, B or '
        'B, A, Then it comes back as it is: 3000 m', () async {
      for (final blocks in [
        [at(1000), at(-1000)],
        [at(-1000), at(1000)],
      ]) {
        final d = lineCosts(start: 0, blocks: blocks);
        for (final order in [
          exactOrder(d),
          await localSearchOrder(d),
          await bestOrder(d),
        ]) {
          expect(order, d.identity());
          expect(d.lengthOf(order), 3000);
        }
      }
    });

    test('Given a start with no point and stops at 1000, 0, 2000, 3000, When '
        'ordered, Then 0, 1000, 2000, 3000: 3000 m, where nearest neighbour '
        'alone gives 4000', () async {
      final blocks = [at(1000), at(0), at(2000), at(3000)];
      final d = lineCosts(start: null, blocks: blocks);
      for (final order in [exactOrder(d), await localSearchOrder(d)]) {
        expect(_positions(blocks, order), [0, 1000, 2000, 3000]);
        expect(d.lengthOf(order), 3000);
      }
      expect(d.lengthOf(nearestNeighbourOrder(d)), 4000);
    });

    test('Given start 0, P at −1000 and Q at 1000, When the end is kept at '
        '−2000, Then Q, P: 4000 m; When it is free, Then P, Q: 3000 m',
        () async {
      final blocks = [at(-1000), at(1000)];
      final kept = lineCosts(start: 0, blocks: blocks, end: -2000);
      for (final order in [exactOrder(kept), await localSearchOrder(kept)]) {
        expect(_positions(blocks, order), [1000, -1000]);
        expect(kept.lengthOf(order), 4000);
      }
      final free = lineCosts(start: 0, blocks: blocks);
      for (final order in [exactOrder(free), await localSearchOrder(free)]) {
        expect(_positions(blocks, order), [-1000, 1000]);
        expect(free.lengthOf(order), 3000);
      }
    });
  });

  group('B. The exact search, up to 12 blocks', () {
    test('Given the nearest-neighbour trap — start 0, stops at 1200, −1000, '
        '2400, 600, 1800 — When ordered, Then −1000, 600, 1200, 1800, 2400: '
        '4400 m, where nearest neighbour alone gives 5800', () {
      final blocks = [at(1200), at(-1000), at(2400), at(600), at(1800)];
      final d = lineCosts(start: 0, blocks: blocks);
      final order = exactOrder(d);
      expect(_positions(blocks, order), [-1000, 600, 1200, 1800, 2400]);
      expect(d.lengthOf(order), 4400);
      expect(d.lengthOf(nearestNeighbourOrder(d)), 5800);
    });

    test('Given start 0, a leg L from 0 to 10000, S1 at 10100 and S2 at 100, '
        'When ordered, Then S2, L, S1: 300 m — a leg is left from its exit, '
        'and taken the wrong way round the answer changes', () {
      final d =
          lineCosts(start: 0, blocks: [leg(0, 10000), at(10100), at(100)]);
      final order = exactOrder(d);
      expect(order, [0, 3, 1, 2, 4]);
      expect(d.lengthOf(order), 300);
      final mixedUp =
          lineCosts(start: 0, blocks: [leg(10000, 0), at(10100), at(100)]);
      final other = exactOrder(mixedUp);
      expect(
          !listEquals(other, order) || mixedUp.lengthOf(other) != 300, isTrue);
    });

    test('Given start 0, C at 2000, B and A both at 1000, When the input is '
        'C, B, A, Then B, A, C: 2000 m — stops at one place keep their order',
        () {
      final d = lineCosts(start: 0, blocks: [at(2000), at(1000), at(1000)]);
      final order = exactOrder(d);
      expect(order, [0, 2, 3, 1, 4]);
      expect(d.lengthOf(order), 2000);
    });

    test('Given a round trip from 0 already at its best, When the input is '
        '600, 1200, −1000 or 1200, 600, −1000, Then it comes back as it is: '
        '4400 m, one of four orders that long', () {
      const orders = [
        [1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1], //
      ];
      for (final blocks in [
        [at(600), at(1200), at(-1000)],
        [at(1200), at(600), at(-1000)],
      ]) {
        final d = lineCosts(start: 0, blocks: blocks, end: 0);
        expect(exactOrder(d), d.identity());
        expect(d.lengthOf(d.identity()), 4400);
        expect(
            orders.where((o) => d.lengthOf([0, ...o, 4]) == 4400).length, 4);
      }
    });

    // 840 random days of 2–8 blocks: spread out or in clusters, 0–70% legs,
    // every kind of end, some starts with no point, some stops on one point.
    final days = [
      for (var m = 2; m <= 8; m++)
        for (var i = 0; i < 120; i++)
          randomDay(
            m * 1000 + i,
            m,
            clustered: i.isOdd,
            legPercent: (i * 7) % 71,
            end: EndKind.values[i % 3],
            startWithoutPoint: i % 5 == 0,
            samePointPercent: i % 4 == 0 ? 30 : 0,
          ),
    ];

    test('Given 840 random days of 2 to 8 blocks, When ordered, Then the '
        'length and the inversions are brute force\'s — the shortest, then '
        'the fewest inversions — and the score over 256 is the length', () {
      for (final (i, day) in days.indexed) {
        final d = day.costs;
        final (:order, :score) = exactOrderWithScore(d);
        expect(
          (length: d.lengthOf(order), inversions: inversions(order)),
          bruteForce(d),
          reason: 'day $i',
        );
        expect(score ~/ 256, d.lengthOf(order), reason: 'day $i');
      }
    }, testOn: 'vm');

    test('Given each of those days, When its answer is ordered again, Then '
        'exactly the same order comes back', () {
      for (final (i, day) in days.indexed) {
        final again = day.reordered(exactOrder(day.costs));
        expect(exactOrder(again.costs), again.costs.identity(),
            reason: 'day $i');
      }
    }, testOn: 'vm');

    test('Given each of those days, When its blocks are shuffled, Then the '
        'answer is just as short', () {
      final rng = XorShift32(11);
      for (final (i, day) in days.indexed) {
        final blocks = [...day.blocks];
        shuffleWith(blocks, rng);
        final shuffled = PlaneDay(day.start, blocks, day.end);
        expect(shuffled.costs.lengthOf(exactOrder(shuffled.costs)),
            day.costs.lengthOf(exactOrder(day.costs)),
            reason: 'day $i');
      }
    }, testOn: 'vm');

    test('Given exactly 12 movable blocks, When the order is chosen, Then it '
        'is the exact search\'s and never pauses; at 13 it pauses and is the '
        'local search\'s — the limit is "up to 12"', () async {
      var pauses = 0;
      Future<void> pause() async {
        pauses++;
      }

      final at12 = randomDay(1212, 12).costs;
      expect(await bestOrder(at12, pause: pause), exactOrder(at12));
      expect(pauses, 0);
      final at13 = randomDay(1313, 13).costs;
      expect(await bestOrder(at13, pause: pause), await localSearchOrder(at13));
      expect(pauses, greaterThan(0));
    });
  });

  group('C. Above 12 blocks', () {
    test('Given a round trip from 0 of 13 stops already at its best — 7200 '
        'down to 600 every 600 m, then −1000 — When ordered, Then it comes '
        'back as it is: 16400 m, though nearest neighbour finds another order '
        'as long', () async {
      final blocks = [for (var x = 7200; x >= 600; x -= 600) at(x), at(-1000)];
      expect(blocks, hasLength(13));
      final d = lineCosts(start: 0, blocks: blocks, end: 0);
      final order = await localSearchOrder(d);
      expect(order, d.identity());
      expect(d.lengthOf(order), 16400);
      final nearest = nearestNeighbourOrder(d);
      expect(nearest, isNot(d.identity()));
      expect(d.lengthOf(nearest), 16400);
    });

    test('Given 20 blocks at one place 500 m from the start, When ordered, '
        'Then they come back as they are: 500 m', () async {
      final d =
          lineCosts(start: 0, blocks: [for (var i = 0; i < 20; i++) at(500)]);
      final order = await localSearchOrder(d);
      expect(order, d.identity());
      expect(d.lengthOf(order), 500);
    });

    test('Given the nearest-neighbour trap with 20 stops — −1000, and 600 to '
        '11400 every 600 m, shuffled — When ordered, Then −1000 and the rest '
        'in order: 13400 m, where nearest neighbour alone gives 23800',
        () async {
      final blocks = [
        at(-1000),
        for (var x = 600; x <= 11400; x += 600) at(x),
      ];
      expect(blocks, hasLength(20));
      shuffleWith(blocks, XorShift32(15));
      final d = lineCosts(start: 0, blocks: blocks);
      final order = await localSearchOrder(d);
      expect(_positions(blocks, order),
          [-1000, for (var x = 600; x <= 11400; x += 600) x]);
      expect(d.lengthOf(order), 13400);
      expect(d.lengthOf(nearestNeighbourOrder(d)), 23800);
    });

    test('Given a 4 × 5 grid of points 100 m apart, a round trip from one '
        'corner and the other 19 shuffled, When ordered, Then 2000 m',
        () async {
      final points = [
        for (var x = 0; x < 4; x++)
          for (var y = 0; y < 5; y++) (x * 100, y * 100),
      ]..remove((0, 0));
      shuffleWith(points, XorShift32(16));
      final day = PlaneDay((0, 0), [for (final p in points) (p, p)], (0, 0));
      expect(day.costs.lengthOf(await localSearchOrder(day.costs)), 2000);
    });

    test('Given a point every 100 m round a 1000 × 600 m rectangle, a round '
        'trip from a corner and the other 31 shuffled, When ordered, Then '
        '3200 m, round the edge one way or the other', () async {
      final points = <Pt>[
        for (var x = 0; x <= 1000; x += 100) (x, 0),
        for (var y = 100; y <= 600; y += 100) (1000, y),
        for (var x = 900; x >= 0; x -= 100) (x, 600),
        for (var y = 500; y >= 100; y -= 100) (0, y),
      ];
      expect(points, hasLength(32));
      final others = points.sublist(1);
      shuffleWith(others, XorShift32(17));
      final day = PlaneDay((0, 0), [for (final p in others) (p, p)], (0, 0));
      final order = await localSearchOrder(day.costs);
      expect(day.costs.lengthOf(order), 3200);
      final route = day.pointsOf(order);
      for (var i = 0; i + 1 < route.length; i++) {
        expect(planeMetres(route[i], route[i + 1]), 100);
      }
    });

    test('Given start 0, a leg from 0 to 10000, stops at 100 to 600 and at '
        '10100 to 10600 — 13 blocks — When ordered, Then 1800 m, the leg '
        'after every near stop and before every far one', () async {
      final blocks = [
        leg(0, 10000),
        for (var x = 100; x <= 600; x += 100) at(x),
        for (var x = 10100; x <= 10600; x += 100) at(x),
      ];
      expect(blocks, hasLength(13));
      final d = lineCosts(start: 0, blocks: blocks);
      final order = await localSearchOrder(d);
      expect(d.lengthOf(order), 1800);
      final legAt = order.indexOf(1);
      for (var v = 2; v <= 7; v++) {
        expect(order.indexOf(v), lessThan(legAt));
      }
      for (var v = 8; v <= 13; v++) {
        expect(order.indexOf(v), greaterThan(legAt));
      }
    });
  });

  group('D. Building blocks', () {
    test('Given seed 12345, When xorshift32 (13, 17, 5) draws, Then '
        '3336926330, 1697253807, 2816511904, 1955480042, 718842323', () {
      final rng = XorShift32(kOrderSeed);
      expect([for (var i = 0; i < 5; i++) rng.next()],
          [3336926330, 1697253807, 2816511904, 1955480042, 718842323]);
    });

    test('Given seed 0, Then the generator refuses it: its state would stay 0 '
        'forever', () {
      expect(() => XorShift32(0), throwsA(isA<AssertionError>()));
    });

    test('Given 13 to 40 blocks, When 2,000 kicks each are made, Then each '
        'keeps the blocks, the start and the end, cuts B, C and D non-empty, '
        'and changes the order', () {
      for (var m = 13; m <= 40; m++) {
        final rng = XorShift32(kOrderSeed);
        var path = [for (var i = 0; i <= m + 1; i++) i];
        for (var k = 0; k < 2000; k++) {
          final kicked = doubleBridge(path, rng);
          _expectDoubleBridge(path, kicked, 'm=$m, kick $k');
          path = kicked;
        }
      }
    }, testOn: 'vm');

    test('Given random paths of 2 to 12 blocks, When every Or-opt, 2-opt and '
        'swap is looked at, Then each step\'s own change is the length after '
        'less the length before, measured again; and without a probe each '
        'step applies the first move that shortens the path', () {
      var moves = 0, neighbourSwaps = 0, runsToStart = 0, runsToEnd = 0;
      final rng = XorShift32(21);
      final steps = <(MoveKind, _Step)>[
        (MoveKind.orOpt, orOptStep),
        (MoveKind.twoOpt, twoOptStep),
        (MoveKind.swap, swapStep),
      ];
      for (var i = 0; i < 400; i++) {
        final m = 2 + i % 11;
        final day = randomDay(2100 + i, m,
            legPercent: 50,
            end: EndKind.values[i % 3],
            startWithoutPoint: i % 4 == 0,
            clustered: i % 5 == 0);
        final d = day.costs;
        final middle = [for (var v = 1; v <= m; v++) v];
        shuffleWith(middle, rng);
        final p = [0, ...middle, m + 1];
        final before = d.lengthOf(p);
        for (final (kind, step) in steps) {
          final seen = <(MoveKind, int, int, int, int)>[];
          final probed = [...p];
          step(d, probed, (k, a, b, c, change) => seen.add((k, a, b, c, change)));
          expect(probed, p, reason: 'a probe applies nothing');
          // Every move of this kind there is, in the scan's order.
          expect([for (final s in seen) (s.$1, s.$2, s.$3, s.$4)],
              [for (final mv in everyMove(m)) if (mv.$1 == kind) mv]);
          for (final (k, a, b, c, change) in seen) {
            // An integer prefix-sum change cannot be NaN or infinite; one that
            // were would differ from every length measured again.
            final measured = d.lengthOf(applyMove(p, k, a, b, c)) - before;
            if (change != measured) {
              fail('path $i ($p) $k ($a, $b, $c): computed $change, '
                  'measured $measured');
            }
            moves++;
            if (k == MoveKind.swap && b == a + 1) neighbourSwaps++;
            if (k == MoveKind.orOpt && c == 0) runsToStart++;
            if (k == MoveKind.orOpt && c == m) runsToEnd++;
          }
          final applied = [...p];
          final moved = step(d, applied);
          final first = seen.where((s) => s.$5 < 0).firstOrNull;
          expect(moved, first != null, reason: 'path $i $kind');
          expect(
            applied,
            first == null ? p : applyMove(p, first.$1, first.$2, first.$3, first.$4),
            reason: 'path $i $kind',
          );
        }
      }
      expect(moves, greaterThan(50000));
      expect(neighbourSwaps, greaterThan(0));
      expect(runsToStart, greaterThan(0));
      expect(runsToEnd, greaterThan(0));
    }, testOn: 'vm');
  });

  group('E. Rules every answer keeps — random days of 13 to 40 blocks', () {
    final days = [
      for (var i = 0; i < 40; i++)
        randomDay(
          2200 + i,
          13 + i % 28,
          clustered: i % 3 == 0,
          legPercent: i.isEven ? 0 : 40,
          end: EndKind.values[i % 3],
          startWithoutPoint: i % 7 == 0,
          samePointPercent: i % 5 == 0 ? 20 : 0,
        ),
    ];
    late List<List<int>> answers;
    setUpAll(() async {
      answers = [for (final day in days) await localSearchOrder(day.costs)];
    });

    test('Then each holds every block exactly once, the start first and the '
        'end last', () {
      for (final (i, day) in days.indexed) {
        final order = answers[i], m = day.blocks.length;
        expect(order, hasLength(m + 2), reason: 'day $i');
        expect(order.first, 0, reason: 'day $i');
        expect(order.last, m + 1, reason: 'day $i');
        expect(order.sublist(1, m + 1).toSet(),
            {for (var v = 1; v <= m; v++) v},
            reason: 'day $i');
      }
    });

    test('Then its length is the one measured again from the points, every '
        'leg run from its entry to its exit', () {
      for (final (i, day) in days.indexed) {
        final order = answers[i], m = day.blocks.length;
        var total = 0;
        for (var t = 0; t + 1 < order.length; t++) {
          final u = order[t], v = order[t + 1];
          final from = u == 0 ? day.start : day.blocks[u - 1].$2;
          final to = v == m + 1 ? day.end : day.blocks[v - 1].$1;
          if (from != null && to != null) total += planeMetres(from, to);
        }
        expect(day.costs.lengthOf(order), total, reason: 'day $i');
      }
    });

    test('Then none is longer than the input order or nearest neighbour', () {
      for (final (i, day) in days.indexed) {
        final d = day.costs, length = d.lengthOf(answers[i]);
        expect(length, lessThanOrEqualTo(d.lengthOf(d.identity())),
            reason: 'day $i');
        expect(length, lessThanOrEqualTo(d.lengthOf(nearestNeighbourOrder(d))),
            reason: 'day $i');
      }
    });

    test('Then no single Or-opt, 2-opt or swap makes it shorter, every move '
        'measured again', () {
      for (final (i, day) in days.indexed) {
        final d = day.costs, order = answers[i];
        final length = d.lengthOf(order);
        for (final (kind, a, b, c) in everyMove(day.blocks.length)) {
          final after = d.lengthOf(applyMove(order, kind, a, b, c));
          if (after < length) {
            fail('day $i: $kind ($a, $b, $c) shortens $length to $after');
          }
        }
      }
    }, testOn: 'vm');

    test('Then a second run gives every answer again, exactly', () async {
      for (final (i, day) in days.indexed) {
        expect(await localSearchOrder(day.costs), answers[i], reason: 'day $i');
      }
    }, testOn: 'vm');

    test('Then ordering an answer again gives the same order or a strictly '
        'shorter one, nothing else', () async {
      for (final (i, day) in days.indexed) {
        final again = day.reordered(answers[i]);
        final d = again.costs;
        final order = await localSearchOrder(d);
        if (!listEquals(order, d.identity())) {
          expect(d.lengthOf(order), lessThan(d.lengthOf(d.identity())),
              reason: 'day $i');
        }
      }
    }, testOn: 'vm');
  });

  test('Given 120 spread-out days of stops only, When ordered, Then no path '
      'crosses itself where undoing it would save 2 m or more — where nearest '
      'neighbour alone does', () async {
    var nearestCrossed = 0;
    for (var i = 0; i < 120; i++) {
      final day = randomDay(2800 + i, 13 + i % 28, end: EndKind.values[i % 3]);
      final d = day.costs;
      final order = await localSearchOrder(d);
      expect(worstCrossingSaving(day.pointsOf(order)), lessThan(2.0),
          reason: 'day $i');
      if (worstCrossingSaving(day.pointsOf(nearestNeighbourOrder(d))) >= 2.0) {
        nearestCrossed++;
      }
    }
    expect(nearestCrossed, greaterThan(60),
        reason: 'the check can fail: nearest neighbour crossed $nearestCrossed');
  }, testOn: 'vm');

  test('Given 150 days of 13 blocks, 150 of 14 and 60 of 16, When the local '
      'search is held to the exact answer, Then it is as short on at least '
      '95% of the days, and never more than 5% longer', () async {
    for (final (m, count) in [(13, 150), (14, 150), (16, 60)]) {
      var asShort = 0;
      var worst = 0.0;
      for (var i = 0; i < count; i++) {
        final day = randomDay(m * 10000 + i, m,
            clustered: i % 3 == 0,
            legPercent: i.isEven ? 0 : 30,
            end: EndKind.values[i % 3],
            startWithoutPoint: i % 7 == 0);
        final d = day.costs;
        final exact = d.lengthOf(exactOrder(d));
        final local = d.lengthOf(await localSearchOrder(d));
        expect(local, greaterThanOrEqualTo(exact), reason: '$m blocks, day $i');
        expect(local * 100, lessThanOrEqualTo(exact * 105),
            reason: '$m blocks, day $i: $local against $exact');
        if (local == exact) asShort++;
        if (exact > 0 && local / exact - 1 > worst) worst = local / exact - 1;
      }
      expect(asShort * 100, greaterThanOrEqualTo(count * 95),
          reason: '$m blocks: $asShort of $count as short, worst '
              '${(worst * 100).toStringAsFixed(1)}% longer');
    }
  }, testOn: 'vm', timeout: const Timeout(Duration(minutes: 5)));
}
