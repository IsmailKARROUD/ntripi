// widgets/move_stop_to_track_sheet.dart — Bottom sheet for moving a single
// stop into a different track (existing OR brand-new).
//
// THREE ROW TYPES, ONE SHEET (Phase 2c):
//   1. Extract row (only when source has ≥ 2 stops) — promotes the stop into
//      its own new track placed immediately after the source. Quick path.
//   2. Existing-track row (Phase 1) — moves the stop into the chosen track.
//      Disabled with a "Full N/N" badge when the target is at capacity.
//   3. Insertion-gap row (Phase 2c) — creates a brand-new track at the
//      chosen position (before Track 1 / between i and i+1 / after Track N).
//
// SHARED CONSEQUENCES FLOW:
//   Every tap computes the post-move track sequence, checks for orphaned
//   transit segments + whether the source track will empty, and surfaces
//   both via a single combined confirm dialog (`confirmDestructiveAction`).
//   On confirm: delete orphaned segments first, then PATCH the stop with the
//   appropriate body (existing-track or new-track anchors).
//
// WHY DELETE ORPHANED SEGMENTS BEFORE THE MOVE?
//   The existing "Add stop between tracks" flow does the same: a hidden-but-
//   still-present segment in the DB would silently re-appear later if track
//   adjacency is ever restored (Phase 2b's whole-track reorder). Clearing
//   them now keeps the data honest.

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
/// after a successful move so the caller can scroll the destination into
/// view. For new-track moves this is the freshly created track's id (read
/// from the API response).
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

// ---------------------------------------------------------------------------
// Target model — three row kinds the user can tap.
// ---------------------------------------------------------------------------

sealed class _MoveTarget {
  const _MoveTarget();
}

class _ExistingTarget extends _MoveTarget {
  final Track track;
  const _ExistingTarget(this.track);
}

/// New-track target with optional anchors. afterTrack=null → new first track.
/// beforeTrack=null → new last track. Both null is invalid (caller must ensure).
class _NewTrackTarget extends _MoveTarget {
  final Track? afterTrack;
  final Track? beforeTrack;
  final bool isExtract; // pure label hint — mechanically same as a gap
  const _NewTrackTarget({this.afterTrack, this.beforeTrack, this.isExtract = false});
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

  Track get _sourceTrack => widget.tracks.firstWhere(
        (t) => t.id == widget.stop.trackId,
        orElse: () => widget.tracks.first,
      );

  String _primaryName(Track t) {
    if (t.stops.isEmpty) return '(empty track)';
    return t.stops.first.placeName ?? '(unnamed)';
  }

  bool _isAtCapacity(Track t) => t.stops.length >= Track.maxParallelStops;

  /// Simulate the post-move track order for [target] and return every segment
  /// that loses its from→to adjacency. The simulation also drops the source
  /// track when it empties so segments referencing the moved stop are
  /// correctly resolved.
  ///
  /// Skip-track example: tracks [A, B, C], stop X in A is the from-stop of
  /// segment X→Y where Y is in B. User moves X to C.
  ///   - After move: X in C (index 2), Y still in B (index 1).
  ///   - fi=2, ti=1 → ti != fi+1 → orphaned (correct).
  /// The stops are still in adjacent tracks (B and C), but the from→to
  /// direction is reversed. The segment is logically broken and must be deleted.
  List<TransitSegment> _computeOrphanedSegments(_MoveTarget target) {
    final stop = widget.stop;
    final sourceTrackId = stop.trackId;

    // Step 1: build post-move track list with the stop removed from source.
    // Use a synthetic id for the new track to keep stopToTrack stable.
    const newTrackSyntheticId = '__new_track__';
    final List<Track> withoutStop = [];
    for (final t in widget.tracks) {
      if (t.id == sourceTrackId) {
        final remaining = t.stops.where((s) => s.id != stop.id).toList();
        if (remaining.isEmpty) continue; // source dropped
        withoutStop.add(t.copyWith(stops: remaining));
      } else {
        withoutStop.add(t);
      }
    }

    // Step 2: place the stop at its destination.
    final List<Track> newOrder;
    switch (target) {
      case _ExistingTarget(:final track):
        newOrder = [
          for (final t in withoutStop)
            if (t.id == track.id)
              t.copyWith(stops: [...t.stops, stop])
            else
              t,
        ];
      case _NewTrackTarget(:final afterTrack, :final beforeTrack):
        final synthetic = Track(
          id: newTrackSyntheticId,
          itineraryId: widget.itineraryId,
          rank: '',
          stops: [stop],
        );
        if (afterTrack == null && beforeTrack == null) {
          // Defensive — shouldn't happen from the UI. Append to end.
          newOrder = [...withoutStop, synthetic];
          break;
        }
        if (afterTrack == null) {
          // Insert before [beforeTrack] (typically index 0).
          final idx = withoutStop.indexWhere((t) => t.id == beforeTrack!.id);
          newOrder = [
            ...withoutStop.sublist(0, idx == -1 ? 0 : idx),
            synthetic,
            ...withoutStop.sublist(idx == -1 ? 0 : idx),
          ];
        } else {
          // Insert after [afterTrack].
          final idx = withoutStop.indexWhere((t) => t.id == afterTrack.id);
          newOrder = [
            ...withoutStop.sublist(0, idx == -1 ? withoutStop.length : idx + 1),
            synthetic,
            ...withoutStop.sublist(idx == -1 ? withoutStop.length : idx + 1),
          ];
        }
    }

    // Step 3: orphan detection against the simulated order.
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

  Future<void> _onSelectTarget(_MoveTarget target) async {
    if (_busy) return;
    // Defensive checks for the existing-track path.
    if (target is _ExistingTarget) {
      if (target.track.id == widget.stop.trackId) return;
      if (_isAtCapacity(target.track)) return;
    }

    final sourceWillEmpty = _sourceTrack.stops.length == 1;
    final orphaned = _computeOrphanedSegments(target);

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

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _busy = true);
    final notifier =
        ref.read(itineraryDetailProvider(widget.itineraryId).notifier);

    final String destinationTrackId;
    final String destinationLabel;
    try {
      for (final seg in orphaned) {
        await notifier.deleteSegment(seg.id);
      }
      final moved = await switch (target) {
        _ExistingTarget(:final track) =>
          notifier.moveStop(widget.stop.id, targetTrackId: track.id),
        _NewTrackTarget(:final afterTrack, :final beforeTrack) =>
          notifier.moveStop(
            widget.stop.id,
            afterTrackId: afterTrack?.id,
            beforeTrackId: beforeTrack?.id,
          ),
      };
      destinationTrackId = moved.trackId;
      destinationLabel = switch (target) {
        _ExistingTarget(:final track) => '"${_primaryName(track)}"',
        _NewTrackTarget() => 'new track',
      };
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
    widget.onMoved(destinationTrackId);
    messenger.showSnackBar(
      SnackBar(content: Text('Moved to $destinationLabel')),
    );
  }

  // ───── Row builders ────────────────────────────────────────────────────

  Widget _buildExtractRow(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: cs.tertiaryContainer,
        child: Icon(Icons.call_split, size: 14, color: cs.onTertiaryContainer),
      ),
      title: const Text('Extract into its own new track'),
      subtitle: Text(
        'Splits this stop out of "${_primaryName(_sourceTrack)}" — new track lands right after.',
        style: theme.textTheme.bodySmall,
      ),
      onTap: _busy
          ? null
          : () => _onSelectTarget(_NewTrackTarget(
                afterTrack: _sourceTrack,
                beforeTrack: _trackAfter(_sourceTrack),
                isExtract: true,
              )),
    );
  }

  /// The track immediately after [t] in display order, or null if [t] is last.
  Track? _trackAfter(Track t) {
    final idx = widget.tracks.indexWhere((x) => x.id == t.id);
    if (idx < 0 || idx >= widget.tracks.length - 1) return null;
    return widget.tracks[idx + 1];
  }

  Widget _buildGapRow(BuildContext context,
      {required Track? after, required Track? before}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = _gapLabel(after, before);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: cs.outlineVariant,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.add, size: 14, color: cs.onSurfaceVariant),
      ),
      title: Text(label, style: theme.textTheme.bodyMedium),
      onTap: _busy
          ? null
          : () => _onSelectTarget(
                _NewTrackTarget(afterTrack: after, beforeTrack: before),
              ),
    );
  }

  String _gapLabel(Track? after, Track? before) {
    if (after == null && before != null) {
      final n = widget.tracks.indexWhere((t) => t.id == before.id) + 1;
      return 'New track before Track $n';
    }
    if (after != null && before == null) {
      final n = widget.tracks.indexWhere((t) => t.id == after.id) + 1;
      return 'New track after Track $n';
    }
    if (after != null && before != null) {
      final ai = widget.tracks.indexWhere((t) => t.id == after.id) + 1;
      final bi = widget.tracks.indexWhere((t) => t.id == before.id) + 1;
      return 'New track between Track $ai and Track $bi';
    }
    return 'New track';
  }

  Widget _buildExistingTrackRow(
    BuildContext context, {
    required Track t,
    required int displayedNumber,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSource = t.id == widget.stop.trackId;
    final full = _isAtCapacity(t);
    final disabled = isSource || full;
    final mutedColor = Colors.grey.shade400;

    return ListTile(
      enabled: !disabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: disabled
            ? Colors.grey.shade200
            : cs.primary.withValues(alpha: 0.12),
        child: Text(
          '$displayedNumber',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: disabled ? mutedColor : cs.primary,
          ),
        ),
      ),
      title: Text(
        _primaryName(t),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: disabled ? TextStyle(color: mutedColor) : null,
      ),
      subtitle: Text(
        '${t.stops.length} stop${t.stops.length == 1 ? '' : 's'}'
        '${isSource ? '  •  current' : ''}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: disabled ? mutedColor : null),
      ),
      trailing: full && !isSource
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
      onTap: (_busy || disabled)
          ? null
          : () => _onSelectTarget(_ExistingTarget(t)),
    );
  }

  // ───── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rows = <Widget>[];

    // 1. Extract row — only when source has parallels.
    if (_sourceTrack.stops.length >= 2) {
      rows.add(_buildExtractRow(context));
      rows.add(const Divider(height: 1));
    }

    // 2. Interleaved insertion-gap + existing-track rows.
    for (var i = 0; i < widget.tracks.length; i++) {
      final prev = i == 0 ? null : widget.tracks[i - 1];
      final t = widget.tracks[i];
      rows.add(_buildGapRow(context, after: prev, before: t));
      rows.add(_buildExistingTrackRow(context, t: t, displayedNumber: i + 1));
    }
    // Trailing gap after the last track.
    if (widget.tracks.isNotEmpty) {
      rows.add(_buildGapRow(context, after: widget.tracks.last, before: null));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Move stop',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose an existing track, a gap to create a new track, or '
              'extract into its own track. Tracks at the '
              '${Track.maxParallelStops}-stop maximum are disabled.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: rows,
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
