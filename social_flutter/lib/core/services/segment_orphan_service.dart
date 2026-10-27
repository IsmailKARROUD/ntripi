// core/services/segment_orphan_service.dart — Pure function that checks a
// proposed trip layout and returns the transit segments it would break.
//
// Arrange mode changes the order of tracks and which track a stop belongs to,
// all before saving. Every change goes through the same adjacency check over
// the layout as it would be saved, so the screen can mark what breaks while
// the user is still arranging and the save can delete exactly that.
//
// SEGMENT ADJACENCY RULE (the one rule that matters):
//   A segment from-stop → to-stop is "live" only when its from-track is at
//   index i and its to-track is at index i+1 in the displayed order. Any
//   layout that breaks this — including merely reversing the direction —
//   orphans the segment.

import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';

/// Every segment in [segments] whose from-track is not immediately followed by
/// its to-track in [layout] — tracks in order, each with the stops it would
/// hold. Stops may have changed track; only where each one ends up counts.
///
/// Skip-track example (the load-bearing case): tracks [A, B, C], stop X
/// (only stop in A) is the from-stop of segment X→Y where Y is in B. X joins
/// C, so A goes and the layout is [B, C-with-X]. fromTrack=C (index 1),
/// toTrack=B (index 0): `ti != fi + 1` → orphaned. The stops are still in
/// adjacent tracks, but the from→to direction is reversed, so the segment is
/// logically broken and must be deleted.
List<TransitSegment> computeOrphansForLayout({
  required List<Track> layout,
  required List<TransitSegment> segments,
}) {
  final stopToTrack = <String, String>{};
  final trackIndex = <String, int>{};
  for (var i = 0; i < layout.length; i++) {
    trackIndex[layout[i].id] = i;
    for (final s in layout[i].stops) {
      stopToTrack[s.id] = layout[i].id;
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
