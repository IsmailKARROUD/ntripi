// widgets/parallel_stop_group.dart — Swipeable group of parallel stops at the same position.
//
// Displays 1–3 stops at identical itinerary positions as swipeable pages.
// When only one stop exists at a position this renders identically to a plain
// StopCard row. When multiple parallels exist the user can swipe left/right
// and dots below the card show which alternative is active.
//
// The segment shown below the card always belongs to the currently visible
// parallel stop (segments are keyed by from_stop_id, so they naturally differ
// per parallel).
//
// "// stop" button: appears to the right of the card in edit mode whenever
// fewer than 3 parallels exist at this position.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/segment_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';

class ParallelStopGroup extends StatefulWidget {
  /// All stops at the same position, sorted by parallel_position ascending.
  final List<Stop> stops;
  final String currency;
  final String itineraryId;
  final bool editMode;

  /// Returns the outgoing segment for a given stop ID (null if none).
  final TransitSegment? Function(String stopId) getSegment;

  /// Called when "+ // stop" is tapped — receives the position to add at.
  final void Function(int position)? onAddParallel;

  /// Edit/delete/annotation callbacks forwarded to StopCard.
  final void Function(Stop stop)? onEditStop;
  final void Function(Stop stop)? onAddAnnotation;
  final void Function(Stop stop, Annotation a)? onEditAnnotation;
  final void Function(Stop stop, Annotation a)? onDeleteAnnotation;

  /// Segment callbacks forwarded to SegmentCard.
  final void Function(TransitSegment seg)? onEditSegment;
  final void Function(TransitSegment seg)? onDeleteSegment;

  const ParallelStopGroup({
    super.key,
    required this.stops,
    required this.currency,
    required this.itineraryId,
    required this.editMode,
    required this.getSegment,
    this.onAddParallel,
    this.onEditStop,
    this.onAddAnnotation,
    this.onEditAnnotation,
    this.onDeleteAnnotation,
    this.onEditSegment,
    this.onDeleteSegment,
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
    final hasParallels = widget.stops.length > 1;
    final canAddMore = widget.stops.length < 3;
    final segment = widget.getSegment(_activeStop.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Stop card row (swipeable) + "// stop" button ──────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: hasParallels
                  ? SizedBox(
                      // Constrain height so the PageView doesn't expand unboundedly.
                      // StopCard is intrinsically ~100-180px; 260 covers annotations.
                      height: 230,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: widget.stops.length,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        itemBuilder: (_, i) => _buildStopCard(widget.stops[i]),
                      ),
                    )
                  : _buildStopCard(widget.stops.first),
            ),
            if (widget.editMode && canAddMore) ...[
              const SizedBox(width: 4),
              _AddParallelButton(
                onTap: widget.onAddParallel == null
                    ? null
                    : () => widget.onAddParallel!(_activeStop.position),
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
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                  ),
                );
              }),
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
      onEdit: widget.editMode && widget.onEditStop != null
          ? () => widget.onEditStop!(stop)
          : null,
      onAddAnnotation: widget.editMode && widget.onAddAnnotation != null
          ? () => widget.onAddAnnotation!(stop)
          : null,
      onEditAnnotation: widget.editMode && widget.onEditAnnotation != null
          ? (a) => widget.onEditAnnotation!(stop, a)
          : null,
      onDeleteAnnotation: widget.editMode && widget.onDeleteAnnotation != null
          ? (a) => widget.onDeleteAnnotation!(stop, a)
          : null,
    );
  }
}

class _AddParallelButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _AddParallelButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.call_split,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 2),
              Text(
                '// stop',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
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
