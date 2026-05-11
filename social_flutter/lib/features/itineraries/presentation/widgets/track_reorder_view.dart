// widgets/track_reorder_view.dart — Full-screen "Reorder tracks" mode.
//
// Replaces the detail screen body when _reorderMode is true. Renders a list
// of collapsed track rows that the user can drag to reorder the entire trip
// sequence. As the order changes, transit segments whose from-track no longer
// immediately precedes their to-track become orphaned — they're surfaced
// both via a top summary banner and an inline red strip below each affected
// track row.
//
// On Save: confirm dialog (only if there are orphans), then a single POST
// /reorder with track_order + segments_to_delete. On success the host screen
// flips _reorderMode off via the onExit callback.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class TrackReorderView extends ConsumerStatefulWidget {
  final String itineraryId;
  final List<Track> tracks;
  final List<TransitSegment> segments;

  /// Called when the view should exit reorder mode — after a successful Save,
  /// after a confirmed Cancel/discard, or on intercepted back navigation.
  final VoidCallback onExit;

  const TrackReorderView({
    super.key,
    required this.itineraryId,
    required this.tracks,
    required this.segments,
    required this.onExit,
  });

  @override
  ConsumerState<TrackReorderView> createState() => _TrackReorderViewState();
}

class _TrackReorderViewState extends ConsumerState<TrackReorderView> {
  late List<Track> _local;
  late List<String> _initialOrder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _local = List.of(widget.tracks);
    _initialOrder = widget.tracks.map((t) => t.id).toList();
  }

  bool get _dirty {
    if (_local.length != _initialOrder.length) return true;
    for (var i = 0; i < _local.length; i++) {
      if (_local[i].id != _initialOrder[i]) return true;
    }
    return false;
  }

  /// Simulate the post-reorder track sequence and return every segment whose
  /// from-track no longer immediately precedes its to-track. Stops don't
  /// change tracks in this view — only the tracks themselves are reordered.
  List<TransitSegment> _computeOrphanedSegments(List<Track> order) {
    final stopToTrack = <String, String>{};
    final trackIndex = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      trackIndex[order[i].id] = i;
      for (final s in order[i].stops) {
        stopToTrack[s.id] = order[i].id;
      }
    }
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

  /// Map of trackId → segments whose from-stop is in that track AND would be
  /// orphaned in the current local order. Used to render the inline red
  /// strip beneath each affected track row.
  Map<String, List<TransitSegment>> _orphansByFromTrack(
      List<TransitSegment> orphans) {
    final stopToTrack = <String, String>{
      for (final t in _local)
        for (final s in t.stops) s.id: t.id,
    };
    final result = <String, List<TransitSegment>>{};
    for (final seg in orphans) {
      final t = stopToTrack[seg.fromStopId];
      if (t == null) continue;
      result.putIfAbsent(t, () => []).add(seg);
    }
    return result;
  }

  String _primaryName(Track t) {
    if (t.stops.isEmpty) return '(empty)';
    return t.stops.first.placeName ?? '(unnamed)';
  }

  String _stopName(String stopId) {
    for (final t in _local) {
      for (final s in t.stops) {
        if (s.id == stopId) return s.placeName ?? '(unnamed)';
      }
    }
    return '(unknown)';
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (_busy) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final moved = _local.removeAt(oldIndex);
      _local.insert(newIndex, moved);
    });
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    return confirmDestructiveAction(
      context: context,
      title: 'Discard changes?',
      message: 'Your reorder will not be saved.',
      confirmLabel: 'Discard',
    );
  }

  Future<void> _onCancel() async {
    final ok = await _confirmDiscardIfDirty();
    if (!ok || !mounted) return;
    widget.onExit();
  }

  Future<void> _onSave() async {
    if (_busy || !_dirty) return;

    final orphaned = _computeOrphanedSegments(_local);
    final messenger = ScaffoldMessenger.of(context);

    if (orphaned.isNotEmpty) {
      final lines = orphaned.map((seg) =>
              '• ${_stopName(seg.fromStopId)} → ${_stopName(seg.toStopId)}')
          .join('\n');
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: 'Save reorder?',
        message:
            '${orphaned.length} transit segment(s) will be deleted because '
            'their stops will no longer be in adjacent tracks:\n\n$lines',
        confirmLabel: 'Save',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .applyReorder(
            trackOrder: _local.map((t) => t.id).toList(),
            segmentIdsToDelete:
                orphaned.isEmpty ? null : orphaned.map((s) => s.id).toList(),
          );
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
    widget.onExit();
    messenger.showSnackBar(const SnackBar(content: Text('Order saved')));
  }

  @override
  Widget build(BuildContext context) {
    final orphans = _computeOrphanedSegments(_local);
    final orphansByTrack = _orphansByFromTrack(orphans);

    return PopScope(
      // Always intercept: back never navigates away while reorder mode is
      // on. It exits reorder mode (with a discard-confirm when dirty).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        final ok = await _confirmDiscardIfDirty();
        if (ok && mounted) widget.onExit();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (orphans.isNotEmpty)
            _OrphanSummaryBanner(
              count: orphans.length,
              entries: orphans
                  .take(3)
                  .map((seg) =>
                      '${_stopName(seg.fromStopId)} → ${_stopName(seg.toStopId)}')
                  .toList(),
              moreCount: orphans.length > 3 ? orphans.length - 3 : 0,
            ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              buildDefaultDragHandles: false,
              itemCount: _local.length,
              onReorder: _onReorder,
              itemBuilder: (_, i) {
                final t = _local[i];
                final affected = orphansByTrack[t.id] ?? const [];
                return _TrackRow(
                  key: ValueKey(t.id),
                  trackNumber: i + 1,
                  primaryName: _primaryName(t),
                  parallelCount: t.stops.length,
                  affected: affected
                      .map((seg) => _stopName(seg.toStopId))
                      .toList(),
                  index: i,
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_busy || !_dirty) ? null : _onSave,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrphanSummaryBanner extends StatelessWidget {
  final int count;
  final List<String> entries;
  final int moreCount;

  const _OrphanSummaryBanner({
    required this.count,
    required this.entries,
    required this.moreCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: cs.error),
              const SizedBox(width: 6),
              Text(
                count == 1
                    ? '1 transit segment will be deleted'
                    : '$count transit segments will be deleted',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                e,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ),
          if (moreCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                '… and $moreCount more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onErrorContainer,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final int trackNumber;
  final String primaryName;
  final int parallelCount;
  final List<String> affected;
  final int index;

  const _TrackRow({
    super.key,
    required this.trackNumber,
    required this.primaryName,
    required this.parallelCount,
    required this.affected,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    child: Text(
                      '$trackNumber',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      primaryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  if (parallelCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$parallelCount alts',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final destName in affected)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 2),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, size: 14, color: cs.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '→ $destName  —  segment will be deleted',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
