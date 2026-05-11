// widgets/move_stop_to_track_sheet.dart — Bottom sheet for moving a single
// stop into a different existing track.
//
// FLOW:
//   1. Sheet lists every track in the itinerary EXCEPT the stop's current one.
//   2. User taps a target row.
//   3. If the move would (a) delete the source track because it goes empty,
//      and/or (b) orphan one or more transit segments (because the moved stop
//      is a segment endpoint and the resulting track relationship is no longer
//      adjacent), a single combined confirm dialog summarises the consequences.
//   4. On confirm: delete the orphaned segments (one DELETE each), then PATCH
//      the stop with the new track_id. The backend appends to the target tail.
//   5. On success: pop the sheet, surface a snackbar, and tell the caller to
//      scroll to the destination (so the user can see where the stop landed).
//
// WHY DELETE ORPHANED SEGMENTS BEFORE THE MOVE?
//   The existing "Add stop between tracks" flow at
//   itinerary_detail_screen.dart already deletes orphaned segments client-side
//   for the same reason: a hidden-but-still-present segment in the DB would
//   silently re-appear later if track adjacency is ever restored (e.g. during
//   Phase 2's whole-track reorder). Clearing them now keeps the data honest.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

/// Launches the sheet. [onMoved] is invoked with the destination track ID
/// after a successful move so the caller can scroll the destination into view.
Future<void> showMoveStopToTrackSheet({
  required BuildContext context,
  required String itineraryId,
  required Stop stop,
  required List<Track> tracks,
  required List<TransitSegment> segments,
  required void Function(String trackId) onMoved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveStopToTrackSheet(
      itineraryId: itineraryId,
      stop: stop,
      tracks: tracks,
      segments: segments,
      onMoved: onMoved,
    ),
  );
}

class _MoveStopToTrackSheet extends ConsumerStatefulWidget {
  final String itineraryId;
  final Stop stop;
  final List<Track> tracks;
  final List<TransitSegment> segments;
  final void Function(String trackId) onMoved;

  const _MoveStopToTrackSheet({
    required this.itineraryId,
    required this.stop,
    required this.tracks,
    required this.segments,
    required this.onMoved,
  });

  @override
  ConsumerState<_MoveStopToTrackSheet> createState() =>
      _MoveStopToTrackSheetState();
}

class _MoveStopToTrackSheetState extends ConsumerState<_MoveStopToTrackSheet> {
  bool _busy = false;

  /// Simulate the post-move track order, then return every segment that loses
  /// its from→to track adjacency. Active-parallel selection is intentionally
  /// ignored — that's a transient UI state, not a data-level concern.
  ///
  /// Skip-track example: tracks [A, B, C], stop X in A is the from-stop of
  /// segment X→Y where Y is in B. User moves X to C.
  ///   - After move: X in C (index 2), Y still in B (index 1).
  ///   - fi=2, ti=1 → ti != fi+1 → orphaned (correct).
  /// The stops are still in adjacent tracks (B and C), but the from→to
  /// direction is reversed. The segment is logically broken and must be
  /// deleted.
  List<TransitSegment> _computeOrphanedSegments(String targetTrackId) {
    final stop = widget.stop;
    final sourceTrackId = stop.trackId;

    // Build the post-move track list. Tracks come in pre-sorted by rank.
    final List<Track> newOrder = [];
    for (final t in widget.tracks) {
      if (t.id == sourceTrackId) {
        // Strip the moved stop. If the track empties, drop it from the order.
        final remaining = t.stops.where((s) => s.id != stop.id).toList();
        if (remaining.isEmpty) continue;
        newOrder.add(t.copyWith(stops: remaining));
      } else if (t.id == targetTrackId) {
        // Append the moved stop to the target's tail.
        newOrder.add(t.copyWith(stops: [...t.stops, stop]));
      } else {
        newOrder.add(t);
      }
    }

    // Map every stop ID to its post-move track ID for O(1) lookup.
    final stopToTrack = <String, String>{};
    for (final t in newOrder) {
      for (final s in t.stops) {
        stopToTrack[s.id] = t.id;
      }
    }
    final trackIndex = <String, int>{
      for (var i = 0; i < newOrder.length; i++) newOrder[i].id: i,
    };

    final orphaned = <TransitSegment>[];
    for (final seg in widget.segments) {
      final fromTrack = stopToTrack[seg.fromStopId];
      final toTrack = stopToTrack[seg.toStopId];
      if (fromTrack == null || toTrack == null) continue;
      final fi = trackIndex[fromTrack];
      final ti = trackIndex[toTrack];
      if (fi == null || ti == null) continue;
      if (ti != fi + 1) orphaned.add(seg);
    }
    return orphaned;
  }

  String _primaryName(Track t) {
    if (t.stops.isEmpty) return '(empty track)';
    return t.stops.first.placeName ?? '(unnamed)';
  }

  bool _isAtCapacity(Track t) => t.stops.length >= Track.maxParallelStops;

  Future<void> _onSelectTarget(Track target) async {
    if (_busy) return;
    if (target.id == widget.stop.trackId) return;
    // Defensive: a stale tap on a row whose track has filled up since the
    // sheet was opened should not slip through. The disabled-state UI already
    // sets onTap: null for capacity-bound rows, but data can change underfoot.
    if (_isAtCapacity(target)) return;

    final sourceTrack = widget.tracks
        .firstWhere((t) => t.id == widget.stop.trackId, orElse: () => target);
    final sourceWillEmpty = sourceTrack.stops.length == 1;
    final orphaned = _computeOrphanedSegments(target.id);

    // Build a single confirm message for the combined consequences.
    if (sourceWillEmpty || orphaned.isNotEmpty) {
      final lines = <String>[];
      if (sourceWillEmpty) {
        lines.add(
          'This is the last stop in its track — the track will be removed '
          'from the itinerary.',
        );
      }
      if (orphaned.isNotEmpty) {
        final n = orphaned.length;
        lines.add(
          n == 1
              ? '1 transit segment will be deleted because its stops will no '
                  'longer be in adjacent tracks.'
              : '$n transit segments will be deleted because their stops will '
                  'no longer be in adjacent tracks.',
        );
      }
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: 'Move stop?',
        message: lines.join('\n\n'),
        confirmLabel: 'Move',
      );
      if (!confirmed || !mounted) return;
    }

    // Capture messenger + navigator before the awaits — context may be gone
    // by the time we want to use them after the move (sheet pops first).
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _busy = true);
    final notifier =
        ref.read(itineraryDetailProvider(widget.itineraryId).notifier);

    try {
      for (final seg in orphaned) {
        await notifier.deleteSegment(seg.id);
      }
      await notifier.moveStop(widget.stop.id, targetTrackId: target.id);
    } on ItineraryStaleException {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Itinerary changed elsewhere — close and reopen to see the latest order.',
          ),
        ),
      );
      return;
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
      return;
    }

    if (!mounted) return;
    navigator.pop();
    widget.onMoved(target.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Moved to "${_primaryName(target)}"'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Filter out the source track so the user can't pick it.
    final targets = widget.tracks
        .where((t) => t.id != widget.stop.trackId)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Move to another track',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a target track. The stop will be appended to its end — '
              'you can reorder within the track afterwards. Tracks already at '
              'the ${Track.maxParallelStops}-stop maximum are shown disabled.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: targets.length,
                itemBuilder: (_, i) {
                  final t = targets[i];
                  // 1-based track number from the FULL track list (not the
                  // filtered one) so the user sees the same numbering as in
                  // the main view.
                  final displayedTrackNumber =
                      widget.tracks.indexWhere((x) => x.id == t.id) + 1;
                  final full = _isAtCapacity(t);
                  final mutedColor = Colors.grey.shade400;
                  return ListTile(
                    enabled: !full,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: full
                          ? Colors.grey.shade200
                          : theme.colorScheme.primary
                              .withValues(alpha: 0.12),
                      child: Text(
                        '$displayedTrackNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              full ? mutedColor : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      _primaryName(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: full ? TextStyle(color: mutedColor) : null,
                    ),
                    subtitle: Text(
                      '${t.stops.length} stop${t.stops.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: full ? mutedColor : null),
                    ),
                    trailing: full
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Full ${Track.maxParallelStops}/${Track.maxParallelStops}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : null,
                    onTap: (_busy || full) ? null : () => _onSelectTarget(t),
                  );
                },
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
