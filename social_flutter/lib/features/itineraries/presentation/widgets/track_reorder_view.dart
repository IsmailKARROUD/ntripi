// widgets/track_reorder_view.dart — Bottom sheet for reordering tracks.
//
// Renders a list of collapsed track rows that the user can drag to reorder
// the entire trip sequence. As the order changes, transit segments whose
// from-track no longer immediately precedes their to-track become orphaned —
// surfaced via a top summary banner and an inline red strip below each row.
//
// On Save: confirm dialog (only if there are orphans), then a single POST
// /reorder with track_order + segments_to_delete. On success the sheet pops.

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
import 'package:social_flutter/l10n/app_localizations.dart';

Future<void> showTrackReorderSheet({
  required BuildContext context,
  required String itineraryId,
  required List<Track> tracks,
  required List<TransitSegment> segments,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TrackReorderSheet(
      itineraryId: itineraryId,
      tracks: tracks,
      segments: segments,
    ),
  );
}

class _TrackReorderSheet extends ConsumerStatefulWidget {
  final String itineraryId;
  final List<Track> tracks;
  final List<TransitSegment> segments;

  const _TrackReorderSheet({
    required this.itineraryId,
    required this.tracks,
    required this.segments,
  });

  @override
  ConsumerState<_TrackReorderSheet> createState() => _TrackReorderSheetState();
}

class _TrackReorderSheetState extends ConsumerState<_TrackReorderSheet> {
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
    final l10n = AppLocalizations.of(context)!;
    if (t.stops.isEmpty) return l10n.emptyTrackName;
    return t.stops.first.placeName ?? l10n.unnamedStop;
  }

  String _stopName(String stopId) {
    final l10n = AppLocalizations.of(context)!;
    for (final t in _local) {
      for (final s in t.stops) {
        if (s.id == stopId) return s.placeName ?? l10n.unnamedStop;
      }
    }
    return l10n.unknownStop;
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
    final l10n = AppLocalizations.of(context)!;
    return confirmDestructiveAction(
      context: context,
      title: l10n.discardChangesTitle,
      message: l10n.discardReorderMessage,
      confirmLabel: l10n.discardButton,
    );
  }

  Future<void> _onCancel() async {
    final ok = await _confirmDiscardIfDirty();
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onSave() async {
    if (_busy || !_dirty) return;

    final orphaned = computeOrphansForTrackReorder(
        newTrackOrder: _local, segments: widget.segments);
    final messenger = ScaffoldMessenger.of(context);

    if (orphaned.isNotEmpty) {
      final lines = orphaned
          .map((seg) =>
              '• ${_stopName(seg.fromStopId)} → ${_stopName(seg.toStopId)}')
          .join('\n');
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: l10n.reorderOrphanTitle,
        message: l10n.reorderOrphanMessage(orphaned.length, lines),
        confirmLabel: l10n.save,
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
        SnackBar(
          content: Text(AppLocalizations.of(context)!.itineraryChangedElsewhere),
        ),
      );
      return;
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.orderSavedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final orphans = computeOrphansForTrackReorder(
        newTrackOrder: _local, segments: widget.segments);
    final orphansByTrack = _orphansByFromTrack(orphans);

    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Container(
        color: kSand,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Orphan warning banner ────────────────────────────────
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

                // ── Section label ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                  child: Text(
                    AppLocalizations.of(context)!
                        .dragToChangeTrackOrder
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // ── Track rows inside one SectionCard ───────────────────
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.60,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      buildDefaultDragHandles: false,
                      itemCount: _local.length,
                      onReorder: _onReorder,
                      proxyDecorator: (child, _, animation) => AnimatedBuilder(
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

                // ── Progress + buttons ───────────────────────────────────
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: kForest,
                      backgroundColor: kMist,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _onCancel,
                      style: TextButton.styleFrom(foregroundColor: kForest),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: (_busy || !_dirty) ? null : _onSave,
                      child: Text(AppLocalizations.of(context)!.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      margin: const EdgeInsets.only(bottom: 8),
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
                  AppLocalizations.of(context)!
                      .transitSegmentsWillBeDeleted(count),
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
                AppLocalizations.of(context)!.andMoreCount(moreCount),
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
        // ── Main row ──────────────────────────────────────────────────────
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kMist,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.altsCount(parallelCount),
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

        // ── Affected-segment strip ─────────────────────────────────────
        for (final destName in affected)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 14, 4),
            child: Row(
              children: [
                const Icon(Icons.cancel_outlined, size: 13, color: kRatingRed),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!
                        .segmentToWillBeDeleted(destName),
                    style: const TextStyle(fontSize: 11, color: kRatingRed),
                  ),
                ),
              ],
            ),
          ),

        // ── Row divider ────────────────────────────────────────────────
        if (showDivider) Container(height: 1, color: kBorder),
      ],
    );
  }
}
