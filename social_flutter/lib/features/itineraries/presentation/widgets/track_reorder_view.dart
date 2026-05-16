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
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/services/segment_orphan_service.dart';
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

    final orphaned = computeOrphansForTrackReorder(newTrackOrder: _local, segments: widget.segments);
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
    final orphans = computeOrphansForTrackReorder(newTrackOrder: _local, segments: widget.segments);
    final orphansByTrack = _orphansByFromTrack(orphans);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        final ok = await _confirmDiscardIfDirty();
        if (ok && mounted) widget.onExit();
      },
      child: ColoredBox(
        color: kSand,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Orphan warning banner ──────────────────────────────────
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

            // ── Subtitle ───────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 10, 22, 6),
              child: Text(
                'DRAG TO CHANGE THE TRACK ORDER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kText2,
                  letterSpacing: 0.6,
                ),
              ),
            ),

            // ── All track rows inside one SectionCard ──────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ReorderableListView.builder(
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    itemCount: _local.length,
                    onReorder: _onReorder,
                    proxyDecorator: (child, _, animation) =>
                        AnimatedBuilder(
                          animation: animation,
                          builder: (_, child) => Material(
                            elevation: 4 * animation.value,
                            shadowColor: Colors.black26,
                            color: kSand,
                            borderRadius: BorderRadius.circular(12),
                            child: child,
                          ),
                          child: child,
                        ),
                    itemBuilder: (_, i) {
                      final t = _local[i];
                      final affected = orphansByTrack[t.id] ?? const [];
                      final isLast = i == _local.length - 1;
                      return _TrackRow(
                        key: ValueKey(t.id),
                        trackNumber: i + 1,
                        primaryName: _primaryName(t),
                        parallelCount: t.stops.length,
                        affected: affected
                            .map((seg) => _stopName(seg.toStopId))
                            .toList(),
                        index: i,
                        showDivider: !isLast,
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── Progress + buttons ─────────────────────────────────────
            if (_busy)
              const LinearProgressIndicator(
                minHeight: 2,
                color: kForest,
                backgroundColor: kMist,
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _onCancel,
                      style:
                          TextButton.styleFrom(foregroundColor: kForest),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kTransitBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kTransitBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: kTransitIcon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 transit segment will be deleted'
                      : '$count transit segments will be deleted',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTransitText,
                  ),
                ),
              ),
            ],
          ),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(left: 24, top: 3),
              child: Text(
                '• $e',
                style: const TextStyle(fontSize: 12, color: kTransitText),
              ),
            ),
          ),
          if (moreCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 3),
              child: Text(
                '… and $moreCount more',
                style: const TextStyle(
                  fontSize: 12,
                  color: kTransitText,
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
  // When true a kBorder divider is drawn at the bottom of the row so adjacent
  // rows inside the shared SectionCard are visually separated.
  final bool showDivider;

  const _TrackRow({
    super.key,
    required this.trackNumber,
    required this.primaryName,
    required this.parallelCount,
    required this.affected,
    required this.index,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Main row ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator_rounded,
                      size: 20, color: kText3),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: kMist,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$trackNumber',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: kForest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  primaryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kBark,
                  ),
                ),
              ),
              if (parallelCount > 1) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kMist,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$parallelCount alts',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kForest,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Affected-segment strip ────────────────────────────────────
        for (final destName in affected)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 14, 4),
            child: Row(
              children: [
                const Icon(Icons.cancel_outlined,
                    size: 13, color: kRatingRed),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '→ $destName  —  segment will be deleted',
                    style: const TextStyle(
                        fontSize: 11, color: kRatingRed),
                  ),
                ),
              ],
            ),
          ),

        // ── Row divider ───────────────────────────────────────────────
        if (showDivider) Container(height: 1, color: kBorder),
      ],
    );
  }
}
