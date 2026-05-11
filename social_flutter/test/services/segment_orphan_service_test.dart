// Unit tests for segment_orphan_service.dart — the pure functions that
// simulate a reorder operation and report orphaned transit segments.
//
// These tests build Stop/Track/TransitSegment instances directly via their
// constructors (no JSON, no Dio, no Riverpod). The service is intentionally
// stateless so the tests can drive it as plain function calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/services/segment_orphan_service.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';

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

void main() {
  group('computeOrphansForStopMove', () {
    test('returns empty when there are no segments at all', () {
      final s1 = _stop('s1', 't1');
      final s2 = _stop('s2', 't2');
      final tracks = [
        _track('t1', 'a0', [s1]),
        _track('t2', 'b0', [s2]),
      ];

      final orphans = computeOrphansForStopMove(
        movedStop: s1,
        target: MoveToExistingTrack(tracks[1]),
        tracks: tracks,
        segments: const [],
      );

      expect(orphans, isEmpty);
    });

    test('returns empty when a move does not affect any segment adjacency', () {
      // tracks [A, B] with parallels in B. Segment A→Y where Y is in B.
      // Move an unrelated parallel within B to a (newly created) track after B.
      final a = _stop('a', 'tA');
      final y = _stop('y', 'tB');
      final z = _stop('z', 'tB');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [y, z]),
      ];
      // Segment A→Y stays adjacent (A still immediately before B).
      // The moved stop is z (not a segment endpoint).

      final orphans = computeOrphansForStopMove(
        movedStop: z,
        target: MoveToNewTrack(afterTrack: tracks[1]),
        tracks: tracks,
        segments: [_seg('seg1', 'a', 'y')],
      );

      expect(orphans, isEmpty);
    });

    test('skip-track move orphans the from-stop\'s segment (Phase 1.1 case)',
        () {
      // tracks [A, B, C], X is the only stop in A and is the from-stop of
      // segment X→Y where Y is in B. User moves X to C as a parallel.
      final x = _stop('x', 'tA');
      final y = _stop('y', 'tB');
      final c1 = _stop('c1', 'tC');
      final tracks = [
        _track('tA', 'a0', [x]),
        _track('tB', 'b0', [y]),
        _track('tC', 'c0', [c1]),
      ];
      final seg = _seg('seg1', 'x', 'y');

      // After move: tA is deleted (X was its only stop), order is [tB, tC+X].
      // fromTrack of seg = tC (index 1), toTrack = tB (index 0). 0 != 1+1 → orphan.
      final orphans = computeOrphansForStopMove(
        movedStop: x,
        target: MoveToExistingTrack(tracks[2]),
        tracks: tracks,
        segments: [seg],
      );

      expect(orphans, hasLength(1));
      expect(orphans.first.id, 'seg1');
    });

    test('inserting a new track between segment endpoints orphans the segment',
        () {
      // tracks [A, B], segment A→B. Move an unrelated stop from elsewhere
      // into a new track between A and B → A is no longer immediately before B.
      final a = _stop('a', 'tA');
      final b = _stop('b', 'tB');
      // X is a parallel of B (so it doesn't delete tB when extracted).
      final x = _stop('x', 'tB');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b, x]),
      ];
      final seg = _seg('seg1', 'a', 'b');

      // Extract X into a new track between tA and tB. tB survives.
      final orphans = computeOrphansForStopMove(
        movedStop: x,
        target: MoveToNewTrack(afterTrack: tracks[0], beforeTrack: tracks[1]),
        tracks: tracks,
        segments: [seg],
      );

      expect(orphans, hasLength(1));
      expect(orphans.first.id, 'seg1');
    });

    test('extracting a non-endpoint parallel produces no orphans', () {
      final a = _stop('a', 'tA');
      final b = _stop('b', 'tB');
      final x = _stop('x', 'tB'); // parallel of b — not a segment endpoint
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b, x]),
      ];
      final seg = _seg('seg1', 'a', 'b');

      // Extract x: new track lands immediately after tB. tA→tB still adjacent.
      final orphans = computeOrphansForStopMove(
        movedStop: x,
        target: MoveToNewTrack(afterTrack: tracks[1]),
        tracks: tracks,
        segments: [seg],
      );

      expect(orphans, isEmpty);
    });

    test('extracting a from-stop into a track between source and to-track keeps adjacency',
        () {
      // tracks [A(=source), B], segment A.x→B.b where x is a parallel of A.
      // Extract x into a new track between A and B → new order [A, new(x), B].
      // fromTrack(seg) = new(x)'s synthetic id (index 1), toTrack = tB (index 2).
      // ti != fi+1 (2 != 1+1 → 2 == 2) → actually adjacent! So no orphan.
      final a1 = _stop('a1', 'tA');
      final x = _stop('x', 'tA');
      final b = _stop('b', 'tB');
      final tracks = [
        _track('tA', 'a0', [a1, x]),
        _track('tB', 'b0', [b]),
      ];
      // Segment is FROM x (now in a new middle track) TO b (still in tB).
      final seg = _seg('seg1', 'x', 'b');

      final orphans = computeOrphansForStopMove(
        movedStop: x,
        target: MoveToNewTrack(afterTrack: tracks[0], beforeTrack: tracks[1]),
        tracks: tracks,
        segments: [seg],
      );

      // x's new track is between tA and tB → x→b is adjacent.
      expect(orphans, isEmpty);
    });

    test('move into an existing track that is the segment\'s to-track keeps adjacency',
        () {
      // tracks [A, B], parallel x in A. Segment A.a1→B.b. Move x into B.
      final a1 = _stop('a1', 'tA');
      final x = _stop('x', 'tA');
      final b = _stop('b', 'tB');
      final tracks = [
        _track('tA', 'a0', [a1, x]),
        _track('tB', 'b0', [b]),
      ];
      final seg = _seg('seg1', 'a1', 'b');

      final orphans = computeOrphansForStopMove(
        movedStop: x,
        target: MoveToExistingTrack(tracks[1]),
        tracks: tracks,
        segments: [seg],
      );

      // tA→tB still adjacent. No orphans.
      expect(orphans, isEmpty);
    });

    test('returns only the orphaned subset when some segments survive', () {
      // tracks [A, B, C], segments A→B (will be orphaned) and B→C (survives).
      // Move A's only stop into a new track between B and C → A deleted,
      // order is [B, new(A), C]. A→B is reversed (orphan). B→C is now non-
      // adjacent (B at 0, C at 2 → orphan).
      // So BOTH are orphaned. Let's pick a scenario where only one is orphaned.
      //
      // Scenario: tracks [A, B, C], segment A→B. Extract a parallel from B
      // into a new track between B and C (not affecting A→B adjacency).
      final a = _stop('a', 'tA');
      final b1 = _stop('b1', 'tB');
      final b2 = _stop('b2', 'tB');
      final c = _stop('c', 'tC');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b1, b2]),
        _track('tC', 'c0', [c]),
      ];
      final segAB = _seg('segAB', 'a', 'b1');
      final segBC = _seg('segBC', 'b1', 'c');

      // Move b2 to new track between B and C. b1 stays in B.
      // After: [A, B(b1), new(b2), C]. A→b1 adjacent (orphan? no, A→B still adjacent).
      // b1→c: fromTrack = tB (1), toTrack = tC (3). 3 != 2 → orphan.
      final orphans = computeOrphansForStopMove(
        movedStop: b2,
        target: MoveToNewTrack(afterTrack: tracks[1], beforeTrack: tracks[2]),
        tracks: tracks,
        segments: [segAB, segBC],
      );

      expect(orphans.map((s) => s.id), ['segBC']);
    });
  });

  group('computeOrphansForTrackReorder', () {
    test('returns empty when the order is unchanged', () {
      final a = _stop('a', 'tA');
      final b = _stop('b', 'tB');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b]),
      ];
      final orphans = computeOrphansForTrackReorder(
        newTrackOrder: tracks,
        segments: [_seg('s1', 'a', 'b')],
      );
      expect(orphans, isEmpty);
    });

    test('reversing a 3-track order with an A→B segment orphans it', () {
      final a = _stop('a', 'tA');
      final b = _stop('b', 'tB');
      final c = _stop('c', 'tC');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b]),
        _track('tC', 'c0', [c]),
      ];
      final reversed = tracks.reversed.toList();

      // Segment A→B: in reversed order, tA is at index 2, tB at index 1.
      // 1 != 2+1 → orphan.
      final orphans = computeOrphansForTrackReorder(
        newTrackOrder: reversed,
        segments: [_seg('s1', 'a', 'b')],
      );

      expect(orphans, hasLength(1));
      expect(orphans.first.id, 's1');
    });

    test('moving an unrelated track does not orphan a segment elsewhere', () {
      // Tracks [A, B, C, D], segment A→B. Move D between A and B is
      // disallowed by adjacency (would orphan), so move D before A instead.
      // Order [D, A, B, C] — A→B still adjacent.
      final a = _stop('a', 'tA');
      final b = _stop('b', 'tB');
      final c = _stop('c', 'tC');
      final d = _stop('d', 'tD');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b]),
        _track('tC', 'c0', [c]),
        _track('tD', 'd0', [d]),
      ];
      final newOrder = [tracks[3], tracks[0], tracks[1], tracks[2]];

      final orphans = computeOrphansForTrackReorder(
        newTrackOrder: newOrder,
        segments: [_seg('s1', 'a', 'b')],
      );

      expect(orphans, isEmpty);
    });

    test('moving a segment-endpoint track to a non-adjacent position orphans it',
        () {
      // tracks [A, B, C, D], segment A→B. Move B to the end: [A, C, D, B].
      // tA index 0, tB index 3 → orphan.
      final a = _stop('a', 'tA');
      final b = _stop('b', 'tB');
      final c = _stop('c', 'tC');
      final d = _stop('d', 'tD');
      final tracks = [
        _track('tA', 'a0', [a]),
        _track('tB', 'b0', [b]),
        _track('tC', 'c0', [c]),
        _track('tD', 'd0', [d]),
      ];
      final newOrder = [tracks[0], tracks[2], tracks[3], tracks[1]];

      final orphans = computeOrphansForTrackReorder(
        newTrackOrder: newOrder,
        segments: [_seg('s1', 'a', 'b')],
      );

      expect(orphans, hasLength(1));
      expect(orphans.first.id, 's1');
    });

    test('empty newTrackOrder returns empty (degenerate)', () {
      final orphans = computeOrphansForTrackReorder(
        newTrackOrder: const [],
        segments: [_seg('s1', 'x', 'y')],
      );
      expect(orphans, isEmpty);
    });
  });
}
