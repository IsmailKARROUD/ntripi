// core/services/segment_orphan_service.dart — Pure functions that simulate a
// reorder operation and return the transit segments whose from-track is no
// longer immediately followed by its to-track in the post-move order.
//
// WHY A SHARED SERVICE?
//   Two reorder UIs need this logic: the move-stop-to-track sheet (where a
//   stop crosses tracks or creates a new one) and the track-reorder view
//   (where stops stay put but tracks shuffle). The algorithm is the same
//   adjacency check (`ti != fi + 1`) over a simulated post-move order; only
//   the simulation differs. Extracting the helpers here makes them testable
//   as plain functions and removes the duplication.
//
// SEGMENT ADJACENCY RULE (the one rule that matters):
//   A segment from-stop → to-stop is "live" only when its from-track is at
//   index i and its to-track is at index i+1 in the displayed order. Any
//   reorder that breaks this — including merely reversing the direction —
//   orphans the segment.

import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';

/// Target of a single-stop move. Mirrors the request shape accepted by
/// `PATCH /itineraries/{id}/stops/{stop_id}`: either an existing track or a
/// brand-new track placed via anchor track ids.
sealed class MoveTarget {
  const MoveTarget();
}

class MoveToExistingTrack extends MoveTarget {
  final Track track;
  const MoveToExistingTrack(this.track);
}

class MoveToNewTrack extends MoveTarget {
  final Track? afterTrack;
  final Track? beforeTrack;
  const MoveToNewTrack({this.afterTrack, this.beforeTrack});
}

const _syntheticNewTrackId = '__new_track__';

/// Simulate moving [movedStop] to [target] inside [tracks] and return every
/// segment in [segments] whose from-track is no longer immediately followed
/// by its to-track in the post-move order. The simulation drops the source
/// track when it empties so segments referencing the moved stop's neighbours
/// see the correct adjacency.
///
/// Active-parallel selection is intentionally ignored — that's a transient
/// UI state, not a data-level concern.
///
/// Skip-track example (the load-bearing case): tracks [A, B, C], stop X
/// (only stop in A) is the from-stop of segment X→Y where Y is in B. User
/// moves X to C. After the move: source track A is deleted; the order is
/// [B, C-with-X-appended]. fromTrack=C (index 1), toTrack=B (index 0).
/// `ti != fi + 1` → orphaned. The stops are still in adjacent tracks, but
/// the from→to direction is reversed, so the segment is logically broken
/// and must be deleted.
List<TransitSegment> computeOrphansForStopMove({
  required Stop movedStop,
  required MoveTarget target,
  required List<Track> tracks,
  required List<TransitSegment> segments,
}) {
  // Step 1: remove the moved stop from its source track. Drop the source
  // track from the order if it empties.
  final List<Track> withoutStop = [];
  for (final t in tracks) {
    if (t.id == movedStop.trackId) {
      final remaining = t.stops.where((s) => s.id != movedStop.id).toList();
      if (remaining.isEmpty) continue;
      withoutStop.add(t.copyWith(stops: remaining));
    } else {
      withoutStop.add(t);
    }
  }

  // Step 2: place the stop at its destination.
  final List<Track> newOrder;
  switch (target) {
    case MoveToExistingTrack(:final track):
      newOrder = [
        for (final t in withoutStop)
          if (t.id == track.id)
            t.copyWith(stops: [...t.stops, movedStop])
          else
            t,
      ];
    case MoveToNewTrack(:final afterTrack, :final beforeTrack):
      final synthetic = Track(
        id: _syntheticNewTrackId,
        itineraryId: movedStop.itineraryId,
        rank: '',
        stops: [movedStop],
      );
      if (afterTrack == null && beforeTrack == null) {
        // Defensive: shouldn't happen from valid call sites. Append.
        newOrder = [...withoutStop, synthetic];
      } else if (afterTrack == null) {
        final idx =
            withoutStop.indexWhere((t) => t.id == beforeTrack!.id);
        newOrder = [
          ...withoutStop.sublist(0, idx == -1 ? 0 : idx),
          synthetic,
          ...withoutStop.sublist(idx == -1 ? 0 : idx),
        ];
      } else {
        final idx = withoutStop.indexWhere((t) => t.id == afterTrack.id);
        newOrder = [
          ...withoutStop.sublist(0, idx == -1 ? withoutStop.length : idx + 1),
          synthetic,
          ...withoutStop.sublist(idx == -1 ? withoutStop.length : idx + 1),
        ];
      }
  }

  return _findOrphans(newOrder, segments);
}

/// Simulate reordering tracks to [newTrackOrder] (same set, different order;
/// stops do not move between tracks) and return every segment that loses
/// from→to track adjacency.
List<TransitSegment> computeOrphansForTrackReorder({
  required List<Track> newTrackOrder,
  required List<TransitSegment> segments,
}) {
  return _findOrphans(newTrackOrder, segments);
}

/// Shared adjacency check. Builds `stop_id → track_id` and `track_id →
/// index` maps over [order], then walks [segments] and reports any whose
/// to-track index isn't exactly from-track index + 1.
List<TransitSegment> _findOrphans(
  List<Track> order,
  List<TransitSegment> segments,
) {
  final stopToTrack = <String, String>{};
  final trackIndex = <String, int>{};
  for (var i = 0; i < order.length; i++) {
    trackIndex[order[i].id] = i;
    for (final s in order[i].stops) {
      stopToTrack[s.id] = order[i].id;
    }
  }

  final orphans = <TransitSegment>[];
  for (final seg in segments) {
    final fromTrack = stopToTrack[seg.fromStopId];
    final toTrack = stopToTrack[seg.toStopId];
    if (fromTrack == null || toTrack == null) continue;
    final fi = trackIndex[fromTrack];
    final ti = trackIndex[toTrack];
    if (fi == null || ti == null) continue;
    if (ti != fi + 1) orphans.add(seg);
  }
  return orphans;
}
