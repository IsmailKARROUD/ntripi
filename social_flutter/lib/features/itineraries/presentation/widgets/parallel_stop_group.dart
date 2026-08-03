// widgets/parallel_stop_group.dart — Swipeable group of stops within one track.
//
// Displays the stops in a track as swipeable pages (1–N stops per track).
// When only one stop exists the card renders as a plain StopCard row.
// When multiple alternatives exist the user can swipe left/right; dots below
// show which alternative is active.
//
// "// stop" button: appears to the right of the card in edit mode and triggers
// adding another stop to the same track (parallel alternative).

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/reorder_parallels_sheet.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/segment_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';
import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

class ParallelStopGroup extends StatefulWidget {
  /// All stops in this track, sorted by rank ascending.
  final List<Stop> stops;
  final String currency;
  final String itineraryId;
  final bool editMode;

  /// 1-based track index shown on the stop card avatar.
  final int trackIndex;

  /// Returns the outgoing segment for a given stop ID (null if none).
  final TransitSegment? Function(String stopId) getSegment;

  /// Called when "+ // stop" is tapped — receives the track ID to add to.
  final void Function(String trackId)? onAddParallel;

  /// Called when the stop card itself is tapped (always, regardless of edit mode).
  final void Function(Stop stop)? onViewStop;

  /// Edit/delete/annotation callbacks forwarded to StopCard.
  final void Function(Stop stop)? onEditStop;
  final void Function(Stop stop)? onAddAnnotation;
  final void Function(Stop stop, Annotation a)? onEditAnnotation;
  final void Function(Stop stop, Annotation a)? onDeleteAnnotation;

  /// Segment callbacks forwarded to SegmentCard.
  final void Function(TransitSegment seg)? onEditSegment;
  final void Function(TransitSegment seg)? onDeleteSegment;

  /// Called when "Add stop" is tapped above this group (first track only).
  final Future<void> Function()? onAddStopBefore;

  /// Called when "Add stop" is tapped below this group.
  final Future<void> Function()? onAddStopAfter;

  /// Called when the active parallel has no segment and the user taps
  /// "Add transit". Receives the active stop's ID as fromStopId.
  final Future<void> Function(String fromStopId)? onAddTransit;

  /// Called whenever the user swipes to a different parallel, with the new index.
  final void Function(int index)? onPageChanged;

  /// True when the itinerary has another track to move this group's active
  /// stop into. Controls visibility of the move-to-track button in edit mode.
  final bool canMoveToTrack;

  /// Called when the user taps the move-to-track button. Receives the active
  /// parallel stop so the parent can launch the target-picker sheet.
  final void Function(Stop activeStop)? onMoveToTrack;

  const ParallelStopGroup({
    super.key,
    required this.stops,
    required this.currency,
    required this.itineraryId,
    required this.editMode,
    required this.trackIndex,
    required this.getSegment,
    this.onAddParallel,
    this.onViewStop,
    this.onEditStop,
    this.onAddAnnotation,
    this.onEditAnnotation,
    this.onDeleteAnnotation,
    this.onEditSegment,
    this.onDeleteSegment,
    this.onAddStopBefore,
    this.onAddStopAfter,
    this.onAddTransit,
    this.onPageChanged,
    this.canMoveToTrack = false,
    this.onMoveToTrack,
  });

  /// The stop currently visible (parallel_position=0 by default).
  /// Exposed so the parent can derive the active stop ID for segment operations.
  Stop get primaryStop => stops.first;

  @override
  State<ParallelStopGroup> createState() => _ParallelStopGroupState();
}

class _ParallelStopGroupState extends State<ParallelStopGroup> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _addStopBeforeLoading = false;
  bool _addStopLoading = false;
  bool _addTransitLoading = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Stop get _activeStop => widget.stops[_currentPage];

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final hasParallels = widget.stops.length > 1;
    final canAddMore = widget.stops.length < Track.maxParallelStops;
    final segment = widget.getSegment(_activeStop.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── "Add stop" before first track (edit mode only) ────────────────
        if (widget.editMode && widget.onAddStopBefore != null)
          OfflineGate(
            builder: (online) => _BottomActionRow(
              showAddStop: true,
              addStopLoading: _addStopBeforeLoading,
              onAddStop: (_addStopBeforeLoading || !online)
                  ? null
                  : () async {
                      setState(() => _addStopBeforeLoading = true);
                      await widget.onAddStopBefore!();
                      if (mounted) {
                        setState(() => _addStopBeforeLoading = false);
                      }
                    },
              showAddTransit: false,
              addTransitLoading: false,
            ),
          ),

        // ── Stop card row (swipeable) + side controls ─────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: hasParallels
                  ? ExpandablePageView.builder(
                    controller: _pageController,
                    itemCount: widget.stops.length,
                    onPageChanged: (i) {
                      setState(() => _currentPage = i);
                      widget.onPageChanged?.call(i);
                    },
                    itemBuilder: (_, i) => Align(
                        alignment: Alignment.topCenter,
                        child: IntrinsicHeight(child: _buildStopCard(widget.stops[i]))),
                  )
                  : _buildStopCard(widget.stops.first),
            ),
            if (widget.editMode &&
                (canAddMore || hasParallels || widget.canMoveToTrack)) ...[
              const SizedBox(width: 4),
              OfflineGate(
                builder: (online) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canAddMore)
                      _AddParallelButton(
                        onTap: (widget.onAddParallel == null || !online)
                            ? null
                            : () => widget.onAddParallel!(_activeStop.trackId),
                      ),
                    if (hasParallels)
                      _ReorderParallelsButton(
                        onTap: !online
                            ? null
                            : () => showReorderParallelsSheet(
                                  context: context,
                                  itineraryId: widget.itineraryId,
                                  stops: widget.stops,
                                ),
                      ),
                    if (widget.canMoveToTrack)
                      _MoveToTrackButton(
                        onTap: (widget.onMoveToTrack == null || !online)
                            ? null
                            : () => widget.onMoveToTrack!(_activeStop),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),

        // ── Dots indicator (only when > 1 parallel) ───────────────────────
        if (hasParallels)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.stops.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 8 : 5,
                  height: active ? 8 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? nt.forest : nt.text3,
                  ),
                );
              }),
            ),
          ),

        // ── Bottom action row: "Add stop" and/or "Add transit" side by side ─
        if (widget.editMode)
          OfflineGate(
            builder: (online) => _BottomActionRow(
              showAddStop: widget.onAddStopAfter != null,
              addStopLoading: _addStopLoading,
              onAddStop: (widget.onAddStopAfter == null || !online)
                  ? null
                  : () async {
                      setState(() => _addStopLoading = true);
                      await widget.onAddStopAfter!();
                      if (mounted) setState(() => _addStopLoading = false);
                    },
              showAddTransit: segment == null && widget.onAddTransit != null,
              addTransitLoading: _addTransitLoading,
              onAddTransit: (widget.onAddTransit == null || !online)
                  ? null
                  : () async {
                      setState(() => _addTransitLoading = true);
                      await widget.onAddTransit!(_activeStop.id);
                      if (mounted) setState(() => _addTransitLoading = false);
                    },
            ),
          ),

        // ── Segment for the active parallel ───────────────────────────────
        if (segment != null)
          SegmentCard(
            key: ValueKey('seg-${segment.id}'),
            segment: segment,
            currency: widget.currency,
            itineraryId: widget.itineraryId,
            onEdit: widget.editMode && widget.onEditSegment != null
                ? () => widget.onEditSegment!(segment)
                : null,
            onDelete: widget.editMode && widget.onDeleteSegment != null
                ? () => widget.onDeleteSegment!(segment)
                : null,
          ),
      ],
    );
  }

  Widget _buildStopCard(Stop stop) {
    return StopCard(
      key: ValueKey(stop.id),
      stop: stop,
      currency: widget.currency,
      trackIndex: widget.trackIndex,
      onTap: widget.onViewStop != null ? () => widget.onViewStop!(stop) : null,
      onEdit: widget.editMode && widget.onEditStop != null
          ? () => widget.onEditStop!(stop)
          : null,
      onAddAnnotation: widget.editMode && widget.onAddAnnotation != null
          ? () => widget.onAddAnnotation!(stop)
          : null,
      onEditAnnotation: widget.editMode && widget.onEditAnnotation != null
          ? (a) => widget.onEditAnnotation!(stop, a)
          : null,
      onDeleteAnnotation:
          widget.editMode && widget.onDeleteAnnotation != null
              ? (a) => widget.onDeleteAnnotation!(stop, a)
              : null,
    );
  }
}

class _BottomActionRow extends StatelessWidget {
  final bool showAddStop;
  final bool addStopLoading;
  final VoidCallback? onAddStop;

  final bool showAddTransit;
  final bool addTransitLoading;
  final VoidCallback? onAddTransit;

  const _BottomActionRow({
    required this.showAddStop,
    required this.addStopLoading,
    this.onAddStop,
    required this.showAddTransit,
    required this.addTransitLoading,
    this.onAddTransit,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    if (!showAddStop && !showAddTransit) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Divider(color: nt.border, height: 1)),
          const SizedBox(width: 8),
          if (showAddStop)
            _ActionChip(
              icon: Icons.add_location_alt_outlined,
              label: l10n.addStopTooltip,
              loading: addStopLoading,
              onTap: addStopLoading ? null : onAddStop,
              color: nt.editBlue,
            ),
          if (showAddStop && showAddTransit)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('·', style: TextStyle(color: nt.text3, fontSize: 12)),
            ),
          if (showAddTransit)
            _ActionChip(
              icon: Icons.directions_transit_outlined,
              label: l10n.addTransitTitle,
              loading: addTransitLoading,
              onTap: addTransitLoading ? null : onAddTransit,
              color: nt.editBlue,
            ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: nt.border, height: 1)),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  // Nullable: theme lookups aren't const, so the default resolves in build.
  final Color? color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.loading,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.nt.text2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: loading
            ? const NTripiRingLoader(size: 13)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 3),
                  Text(label,
                      style: TextStyle(fontSize: 12, color: color)),
                ],
              ),
      ),
    );
  }
}

class _MoveToTrackButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _MoveToTrackButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6, end: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: nt.editBlueTint,
            border: Border.all(color: nt.editBlue.withValues(alpha: 0.13)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: 16, color: nt.editBlue),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context)!.moveActionLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: nt.editBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderParallelsButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ReorderParallelsButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6, end: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: nt.editBlueTint,
            border: Border.all(color: nt.editBlue.withValues(alpha: 0.13)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, size: 16, color: nt.editBlue),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context)!.reorderActionLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: nt.editBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddParallelButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _AddParallelButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8, end: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: nt.editBlueTint,
            border: Border.all(color: nt.editBlue.withValues(alpha: 0.13)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_split, size: 16, color: nt.editBlue),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context)!.addParallelStopLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: nt.editBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
