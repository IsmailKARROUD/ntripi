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
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/services/segment_orphan_service.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

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

// Target row types. The MoveTarget sealed hierarchy (used both here and by
// the orphan-detection service) is imported from segment_orphan_service.dart.

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
  // true while a move API call is in flight — disables all row taps and shows the progress bar
  bool _busy = false;

  Track get _sourceTrack => widget.tracks.firstWhere(
        (t) => t.id == widget.stop.trackId,
        orElse: () => widget.tracks.first,
      );

  String _primaryName(Track t) {
    final l10n = AppLocalizations.of(context)!;
    if (t.stops.isEmpty) return l10n.emptyTrackLabel;
    return t.stops.first.placeName ?? l10n.unnamedStop;
  }

  bool _isAtCapacity(Track t) => t.stops.length >= Track.maxParallelStops;

  Future<void> _onSelectTarget(MoveTarget target) async {
    if (_busy) return;
    // Defensive checks for the existing-track path.
    if (target is MoveToExistingTrack) {
      if (target.track.id == widget.stop.trackId) return;
      if (_isAtCapacity(target.track)) return;
    }

    // Capture all l10n strings before any async gap.
    final l10n = AppLocalizations.of(context)!;
    final newTrackLabel = l10n.moveStopNewTrack;
    final changedElsewhereMsg = l10n.itineraryChangedElsewhere;

    final sourceWillEmpty = _sourceTrack.stops.length == 1;
    final orphaned = computeOrphansForStopMove(
      movedStop: widget.stop,
      target: target,
      tracks: widget.tracks,
      segments: widget.segments,
    );

    if (sourceWillEmpty || orphaned.isNotEmpty) {
      final lines = <String>[];
      if (sourceWillEmpty) lines.add(l10n.moveStopOrphan1);
      if (orphaned.isNotEmpty) lines.add(l10n.moveStopOrphanSegments(orphaned.length));
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: l10n.moveStopTitle,
        message: lines.join('\n\n'),
        confirmLabel: l10n.moveButton,
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
        MoveToExistingTrack(:final track) =>
          notifier.moveStop(widget.stop.id, targetTrackId: track.id),
        MoveToNewTrack(:final afterTrack, :final beforeTrack) =>
          notifier.moveStop(
            widget.stop.id,
            afterTrackId: afterTrack?.id,
            beforeTrackId: beforeTrack?.id,
          ),
      };
      destinationTrackId = moved.trackId;
      destinationLabel = switch (target) {
        MoveToExistingTrack(:final track) => '"${_primaryName(track)}"',
        MoveToNewTrack() => newTrackLabel,
      };
    } on ItineraryStaleException {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(changedElsewhereMsg)));
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
    navigator.pop();
    widget.onMoved(destinationTrackId);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.moveStopMoved(destinationLabel))),
    );
  }

  // ───── Row builders ────────────────────────────────────────────────────

  Widget _buildExtractRow(BuildContext context) {
    return InkWell(
      onTap: _busy
          ? null
          : () => _onSelectTarget(MoveToNewTrack(
                afterTrack: _sourceTrack,
                beforeTrack: _trackAfter(_sourceTrack),
              )),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kMist,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.call_split_rounded,
                  size: 18, color: kForest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.extractIntoOwnTrack,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kBark),
                  ),
                  Text(
                    AppLocalizations.of(context)!
                        .extractSubtitle(_primaryName(_sourceTrack)),
                    style: const TextStyle(fontSize: 11, color: kText2),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: kText3),
          ],
        ),
      ),
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
    final label = _gapLabel(context, after, before);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: _busy
            ? null
            : () => _onSelectTarget(
                  MoveToNewTrack(afterTrack: after, beforeTrack: before),
                ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kText3, style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, size: 14, color: kForest),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kBark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _gapLabel(BuildContext context, Track? after, Track? before) {
    final l10n = AppLocalizations.of(context)!;
    if (after == null && before != null) {
      final n = widget.tracks.indexWhere((t) => t.id == before.id) + 1;
      return l10n.moveStopNewTrackBefore(n);
    }
    if (after != null && before == null) {
      final n = widget.tracks.indexWhere((t) => t.id == after.id) + 1;
      return l10n.moveStopNewTrackAfter(n);
    }
    if (after != null && before != null) {
      final ai = widget.tracks.indexWhere((t) => t.id == after.id) + 1;
      final bi = widget.tracks.indexWhere((t) => t.id == before.id) + 1;
      return l10n.moveStopNewTrackBetween(ai, bi);
    }
    return l10n.moveStopNewTrack;
  }

  Widget _buildExistingTrackRow(
    BuildContext context, {
    required Track t,
    required int displayedNumber,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isSource = t.id == widget.stop.trackId;
    final full = _isAtCapacity(t);
    final disabled = isSource || full;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: InkWell(
        onTap: (_busy || disabled)
            ? null
            : () => _onSelectTarget(MoveToExistingTrack(t)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
          child: Row(
            children: [
              // Number circle
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: disabled ? kBorder : kMist,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$displayedNumber',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: disabled ? kText3 : kForest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _primaryName(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: disabled ? kText3 : kBark,
                      ),
                    ),
                    Text(
                      l10n.stopCount(t.stops.length) +
                          (isSource ? l10n.moveStopCurrentSuffix : ''),
                      style: const TextStyle(
                          fontSize: 11, color: kText2),
                    ),
                  ],
                ),
              ),
              if (full && !isSource)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.moveStopFull(Track.maxParallelStops),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kText3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ───── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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

    // PopScope blocks back-button and barrier-tap dismissal mid-move; the
    // overlay blocks in-sheet taps.
    return PopScope(
      canPop: !_busy,
      child: SavingOverlay(
        saving: _busy,
        loaderSize: 40,
        child: Container(
      color: kSand,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section label
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Text(
                  AppLocalizations.of(context)!.moveStopToLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              // Rows in a white card — capped at 65 % screen height so the
              // sheet never overflows when the itinerary has many tracks.
              // Every row fires a move mutation, so the whole card is gated:
              // offline taps show the popover instead of firing.
              OfflineGate(
                builder: (_) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < rows.length; i++) ...[
                          rows[i],
                          if (i < rows.length - 1)
                            Container(height: 1, color: kBorder),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}
