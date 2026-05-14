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
import 'package:social_flutter/core/services/segment_orphan_service.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: cs.tertiaryContainer,
        child: Icon(Icons.call_split, size: 14, color: cs.onTertiaryContainer),
      ),
      title: Text(AppLocalizations.of(context)!.extractIntoOwnTrack),
      subtitle: Text(
        AppLocalizations.of(context)!.extractSubtitle(_primaryName(_sourceTrack)),
        style: theme.textTheme.bodySmall,
      ),
      onTap: _busy
          ? null
          : () => _onSelectTarget(MoveToNewTrack(
                afterTrack: _sourceTrack,
                beforeTrack: _trackAfter(_sourceTrack),
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
    final label = _gapLabel(context, after, before);
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
                MoveToNewTrack(afterTrack: after, beforeTrack: before),
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
        AppLocalizations.of(context)!.stopCount(t.stops.length) +
        (isSource ? AppLocalizations.of(context)!.moveStopCurrentSuffix : ''),
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
                AppLocalizations.of(context)!.moveStopFull(Track.maxParallelStops),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      onTap: (_busy || disabled)
          ? null
          : () => _onSelectTarget(MoveToExistingTrack(t)),
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
              AppLocalizations.of(context)!.moveStopTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.moveStopDescription(Track.maxParallelStops),
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
