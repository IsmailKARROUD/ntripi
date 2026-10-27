// Unit tests for segment_orphan_service.dart — the pure adjacency check that
// reports the transit segments a proposed layout would break.
//
// The stop moves are made through TripArrangement, exactly as arrange mode
// makes them, so each case checks the layout the screen would save. Plain
// constructors only (no JSON, no Dio, no Riverpod).

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/services/segment_orphan_service.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

// ---------------------------------------------------------------------------
// Fixture builders — concise constructors for value objects.
// ---------------------------------------------------------------------------

const _itinId = 'itin-1';

Stop _stop(String id, String trackId, {String? name}) => Stop(
      id: id,
      itineraryId: _itinId,
      trackId: trackId,
      rank: 'a0',
      placeName: name ?? id,
      placeAddress: null,
      lat: null,
      lng: null,
      placeType: null,
      durationMin: null,
      cost: 0.0,
      isFree: true,
      notes: null,
      type: StopType.waypoint,
      createdAt: DateTime.utc(2026, 1, 1),
      annotations: const [],
    );

Track _track(String id, String rank, List<Stop> stops) => Track(
      id: id,
      itineraryId: _itinId,
      rank: rank,
      stops: stops,
    );

TransitSegment _seg(String id, String from, String to) => TransitSegment(
      id: id,
      itineraryId: _itinId,
      fromStopId: from,
      toStopId: to,
      totalDurationMin: 0,
      totalCost: 0.0,
      legs: const [],
      createdAt: DateTime.utc(2026, 1, 1),
    );

List<String> _orphanIds(TripArrangement arranged, List<TransitSegment> segs) =>
    computeOrphansForLayout(layout: arranged.tracks, segments: segs)
        .map((s) => s.id)
        .toList();

void main() {
  group('stop moves', () {
    test('returns empty when there are no segments at all', () {
      final arranged = TripArrangement.of([
        _track('t1', 'a0', [_stop('s1', 't1')]),
        _track('t2', 'b0', [_stop('s2', 't2')]),
      ]).moveStopToRow('s1', 't2');

      expect(_orphanIds(arranged, const []), isEmpty);
    });

    test('splitting out a parallel that no segment touches breaks nothing', () {
      // tracks [A, B(y, z)], segment a→y. z gets a track of its own after B.
      final arranged = TripArrangement.of([
        _track('tA', 'a0', [_stop('a', 'tA')]),
        _track('tB', 'b0', [_stop('y', 'tB'), _stop('z', 'tB')]),
      ]).moveStopToGap('z', 2);

      expect(_orphanIds(arranged, [_seg('seg1', 'a', 'y')]), isEmpty);
    });

    test("a skip-track join orphans the from-stop's segment", () {
      // tracks [A, B, C]: x alone in A is the from-stop of x→y, y in B. x joins
      // C, A goes, and the layout is [B, C+x]: the segment now runs backwards.
      final arranged = TripArrangement.of([
        _track('tA', 'a0', [_stop('x', 'tA')]),
        _track('tB', 'b0', [_stop('y', 'tB')]),
        _track('tC', 'c0', [_stop('c1', 'tC')]),
      ]).moveStopToRow('x', 'tC');

      expect(_orphanIds(arranged, [_seg('seg1', 'x', 'y')]), ['seg1']);
    });

    test('a new track between the endpoints orphans their segment', () {
      // tracks [A, B(b, x)], segment a→b. x gets its own track between A and B.
      final arranged = TripArrangement.of([
        _track('tA', 'a0', [_stop('a', 'tA')]),
        _track('tB', 'b0', [_stop('b', 'tB'), _stop('x', 'tB')]),
      ]).moveStopToGap('x', 1);

      expect(_orphanIds(arranged, [_seg('seg1', 'a', 'b')]), ['seg1']);
    });

    test('a from-stop split out between source and to-track stays adjacent',
        () {
      // tracks [A(a1, x), B], segment x→b. x gets its own track between A and
      // B: [A, new(x), B], and x→b still runs from one track to the next.
      final arranged = TripArrangement.of([
        _track('tA', 'a0', [_stop('a1', 'tA'), _stop('x', 'tA')]),
        _track('tB', 'b0', [_stop('b', 'tB')]),
      ]).moveStopToGap('x', 1);

      expect(_orphanIds(arranged, [_seg('seg1', 'x', 'b')]), isEmpty);
    });

    test("joining the segment's to-track keeps it adjacent", () {
      // tracks [A(a1, x), B], segment a1→b. x joins B.
      final arranged = TripArrangement.of([
        _track('tA', 'a0', [_stop('a1', 'tA'), _stop('x', 'tA')]),
        _track('tB', 'b0', [_stop('b', 'tB')]),
      ]).moveStopToRow('x', 'tB');

      expect(_orphanIds(arranged, [_seg('seg1', 'a1', 'b')]), isEmpty);
    });

    test('returns only the orphaned subset when some segments survive', () {
      // tracks [A, B(b1, b2), C], segments a→b1 and b1→c. b2 gets its own track
      // between B and C: a→b1 survives, b1→c no longer reaches the next track.
      final arranged = TripArrangement.of([
        _track('tA', 'a0', [_stop('a', 'tA')]),
        _track('tB', 'b0', [_stop('b1', 'tB'), _stop('b2', 'tB')]),
        _track('tC', 'c0', [_stop('c', 'tC')]),
      ]).moveStopToGap('b2', 2);

      expect(
        _orphanIds(arranged, [_seg('segAB', 'a', 'b1'), _seg('segBC', 'b1', 'c')]),
        ['segBC'],
      );
    });
  });

  group('track moves', () {
    final tracks = [
      _track('tA', 'a0', [_stop('a', 'tA')]),
      _track('tB', 'b0', [_stop('b', 'tB')]),
      _track('tC', 'c0', [_stop('c', 'tC')]),
      _track('tD', 'd0', [_stop('d', 'tD')]),
    ];
    final ab = [_seg('s1', 'a', 'b')];

    test('returns empty when the order is unchanged', () {
      expect(_orphanIds(TripArrangement.of(tracks), ab), isEmpty);
    });

    test('reversing the order orphans an A→B segment', () {
      final reversed = computeOrphansForLayout(
        layout: tracks.reversed.toList(),
        segments: ab,
      );
      expect(reversed.map((s) => s.id), ['s1']);
    });

    test('moving an unrelated track does not orphan a segment elsewhere', () {
      // D to the front: [D, A, B, C] — A→B still adjacent.
      final arranged = TripArrangement.of(tracks).moveTrack('tD', 0);
      expect(_orphanIds(arranged, ab), isEmpty);
    });

    test('moving an endpoint track out of reach orphans its segment', () {
      // B to the end: [A, C, D, B].
      final arranged = TripArrangement.of(tracks).moveTrack('tB', 4);
      expect(_orphanIds(arranged, ab), ['s1']);
    });

    test('an empty layout returns empty (degenerate)', () {
      expect(
        computeOrphansForLayout(layout: const [], segments: [_seg('s1', 'x', 'y')]),
        isEmpty,
      );
    });
  });
}
