// widgets/arrange_trip_view.dart — Arrange mode: the trip as compact rows of
// stop chips, where stops and whole tracks move by drag or by tap.
//
// One place owns every structural edit of a trip — the order of its tracks,
// the order of a track's alternatives, and which track a stop belongs to — so
// none of them needs a button of its own on the stop cards, where "reorder"
// and "move" read as the same word. Nothing here saves: every move hands a new
// TripArrangement to [onChanged], and the screen sends it on Save.
//
// TWO WAYS TO MOVE, ONE SET OF TARGETS:
//   Drag: a chip's ⠿ handle drags at once (so it never scrolls the page), and
//   holding a chip drags it too; a track's number drags the whole track. Tap:
//   tap a chip or a number to pick it, then tap where it goes. Either way the
//   targets are the same — a gap between tracks (a track of its own; a track
//   moves there whole), a track (its last alternative), or a stop (before it,
//   which inside its own track is a reorder).
//
// Transit links are checked live against the layout as it stands: what a move
// would break is marked under its track and summed up above the list, so the
// confirmation on Save never comes as a surprise.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ntripi/core/services/segment_orphan_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// What is being moved: one stop, or a whole track.
sealed class _Moving {
  const _Moving();
}

class _MovingStop extends _Moving {
  const _MovingStop(this.stopId);
  final String stopId;
}

class _MovingTrack extends _Moving {
  const _MovingTrack(this.rowKey);
  final String rowKey;
}

class ArrangeTripView extends StatefulWidget {
  const ArrangeTripView({
    super.key,
    required this.arrangement,
    required this.segments,
    required this.onChanged,
  });

  final TripArrangement arrangement;

  /// The trip's transit segments, checked against the layout as it stands.
  final List<TransitSegment> segments;

  final ValueChanged<TripArrangement> onChanged;

  @override
  State<ArrangeTripView> createState() => _ArrangeTripViewState();
}

class _ArrangeTripViewState extends State<ArrangeTripView> {
  // Picked by a tap, waiting for the tap that says where it goes.
  _Moving? _picked;
  // Being dragged right now.
  _Moving? _dragging;
  // A drag opens its targets only once past the slop: opened at the lift, they
  // moved the list under a finger held still, and a tremble dropped it there.
  Offset _dragTravel = Offset.zero;
  bool _dragTravelled = false;
  EdgeDraggingAutoScroller? _autoScroller;

  /// What the rows offer targets for: a drag under way, else a pick.
  _Moving? get _moving => _dragTravelled ? _dragging : _picked;

  TripArrangement get _arrangement => widget.arrangement;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bound to the page's Scrollable; a new one needs a new scroller.
    _autoScroller = null;
  }

  @override
  void didUpdateWidget(covariant ArrangeTripView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final picked = _picked;
    final gone = switch (picked) {
      _MovingStop(:final stopId) => _arrangement.rowOf(stopId) < 0,
      _MovingTrack(:final rowKey) =>
        !_arrangement.rows.any((r) => r.key == rowKey),
      null => false,
    };
    if (gone) _picked = null;
  }

  // ── Moves ────────────────────────────────────────────────────────────────

  void _apply(TripArrangement next) {
    HapticFeedback.selectionClick();
    setState(() => _picked = null);
    widget.onChanged(next);
  }

  void _toGap(_Moving moving, int gap) => _apply(switch (moving) {
        _MovingStop(:final stopId) => _arrangement.moveStopToGap(stopId, gap),
        _MovingTrack(:final rowKey) => _arrangement.moveTrack(rowKey, gap),
      });

  void _toRow(_MovingStop moving, String rowKey, {String? beforeStopId}) =>
      _apply(_arrangement.moveStopToRow(moving.stopId, rowKey,
          beforeStopId: beforeStopId));

  bool _gapTakes(_Moving moving, int gap) => switch (moving) {
        _MovingStop(:final stopId) => !_arrangement.isStopNoOpGap(stopId, gap),
        _MovingTrack(:final rowKey) => !_arrangement.isTrackNoOpGap(rowKey, gap),
      };

  /// A stop picked or dragged from another track, which [row] can take.
  bool _rowTakes(_Moving? moving, ArrangedTrack row) =>
      moving is _MovingStop && _arrangement.accepts(row.key, moving.stopId);

  void _pick(_Moving? moving) {
    HapticFeedback.selectionClick();
    setState(() => _picked = moving);
  }

  void _tapStop(Stop stop, ArrangedTrack row) {
    final picked = _picked;
    if (picked is _MovingStop) {
      if (picked.stopId == stop.id) return _pick(null);
      if (_arrangement.accepts(row.key, picked.stopId)) {
        return _toRow(picked, row.key, beforeStopId: stop.id);
      }
    }
    _pick(_MovingStop(stop.id));
  }

  void _tapTrack(ArrangedTrack row) {
    final picked = _picked;
    _pick(picked is _MovingTrack && picked.rowKey == row.key
        ? null
        : _MovingTrack(row.key));
  }

  // ── Dragging ─────────────────────────────────────────────────────────────

  // Lifting changes nothing around the lifted stop or track: a pick stays drawn
  // until the drag is under way.
  void _dragStarted(_Moving moving) => setState(() {
        _dragging = moving;
        _dragTravel = Offset.zero;
        _dragTravelled = false;
      });

  void _dragUpdated(DragUpdateDetails details) {
    if (!_dragTravelled) {
      _dragTravel += details.delta;
      if (_dragTravel.distance <= kTouchSlop) return;
      setState(() {
        _dragTravelled = true;
        _picked = null;
      });
    }
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    // ReorderableList's own scalar; the rect reaches 48 px either side of the
    // finger, which is how close to an edge the page starts to scroll.
    _autoScroller ??= EdgeDraggingAutoScroller(scrollable, velocityScalar: 50);
    _autoScroller!.startAutoScrollIfNecessary(Rect.fromCenter(
        center: details.globalPosition, width: 1, height: 96));
  }

  // Never onDragEnd: Flutter skips it once the dragged widget is rebuilt.
  void _dragEnded() {
    _autoScroller?.stopAutoScroll();
    if (!mounted) return;
    setState(() {
      _dragging = null;
      _dragTravelled = false;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  String _name(Stop? stop, AppLocalizations l10n) =>
      stop?.placeName ?? l10n.unnamedStop;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final rows = _arrangement.rows;
    final orphans = computeOrphansForLayout(
        layout: _arrangement.tracks, segments: widget.segments);
    final orphanIds = {for (final s in orphans) s.id};
    final moving = _moving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Instructions(
          picked: switch (_picked) {
            _MovingStop(:final stopId) =>
              l10n.arrangeMovingStop(_name(_arrangement.stop(stopId), l10n)),
            _MovingTrack(:final rowKey) => l10n.arrangeMovingTrack(
                rows.indexWhere((r) => r.key == rowKey) + 1),
            null => null,
          },
          onCancel: () => _pick(null),
        ),
        if (orphans.isNotEmpty)
          _BrokenLinksBanner(
            count: orphans.length,
            entries: [
              for (final seg in orphans.take(3))
                '${_name(_arrangement.stop(seg.fromStopId), l10n)} → '
                    '${_name(_arrangement.stop(seg.toStopId), l10n)}',
            ],
            moreCount: orphans.length > 3 ? orphans.length - 3 : 0,
          ),
        Container(
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: nt.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i <= rows.length; i++) ...[
                _gap(i, moving, orphanIds),
                if (i < rows.length) _row(i, rows[i], moving, orphans),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Gap [index] sits before row [index]. While something moves and the gap
  /// would change something, it is a target; otherwise a plain separator.
  Widget _gap(int index, _Moving? moving, Set<String> orphanIds) {
    final rows = _arrangement.rows;
    if (moving == null || !_gapTakes(moving, index)) {
      if (index == 0 || index == rows.length) return const SizedBox.shrink();
      return _Separator(
        linked: _linked(rows[index - 1], rows[index], orphanIds),
      );
    }
    final picked = _picked;
    return DragTarget<_Moving>(
      onWillAcceptWithDetails: (d) => _gapTakes(d.data, index),
      onAcceptWithDetails: (d) => _toGap(d.data, index),
      builder: (context, candidates, _) => _GapTarget(
        hovered: candidates.isNotEmpty,
        onTap: picked == null ? null : () => _toGap(picked, index),
      ),
    );
  }

  /// Whether a transit link runs from [above] to [below] — one that survives
  /// the layout, since adjacent tracks are exactly what keeps one alive.
  bool _linked(ArrangedTrack above, ArrangedTrack below, Set<String> orphanIds) {
    final from = {for (final s in above.stops) s.id};
    final to = {for (final s in below.stops) s.id};
    return widget.segments.any((seg) =>
        !orphanIds.contains(seg.id) &&
        from.contains(seg.fromStopId) &&
        to.contains(seg.toStopId));
  }

  Widget _row(
    int index,
    ArrangedTrack row,
    _Moving? moving,
    List<TransitSegment> orphans,
  ) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final fromElsewhere =
        moving is _MovingStop && _arrangement.rowOf(moving.stopId) != index;
    final takes = fromElsewhere && _rowTakes(moving, row);
    final full = fromElsewhere && !takes;
    final dragging = _dragging;
    // Dimmed from the lift on: a dimmed track moves nothing under the finger.
    final lifted = dragging is _MovingTrack && dragging.rowKey == row.key;
    final picked = _picked;
    final rowStops = {for (final s in row.stops) s.id};
    final breaks = [
      for (final seg in orphans)
        if (rowStops.contains(seg.fromStopId)) seg,
    ];

    return DragTarget<_Moving>(
      key: ValueKey(row.key),
      onWillAcceptWithDetails: (d) => _rowTakes(d.data, row),
      onAcceptWithDetails: (d) => _toRow(d.data as _MovingStop, row.key),
      builder: (context, candidates, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping the track's free space puts the picked stop at its end.
        onTap: _rowTakes(picked, row)
            ? () => _toRow(picked! as _MovingStop, row.key)
            : null,
        // Always a box: one added mid-drag rebuilt the dragged chip away.
        child: ColoredBox(
          color: candidates.isNotEmpty ? nt.mist : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Opacity(
                opacity: lifted ? 0.35 : 1,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 10, 8),
                  child: Row(
                    children: [
                      _trackHandle(index, row),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final stop in row.stops)
                              _chip(stop, row, moving),
                            // After the last chip: where the stop would land.
                            if (takes)
                              _Tag(
                                label: l10n.arrangeAddAsAlternative,
                                icon: Icons.add_rounded,
                                active: true,
                              )
                            else if (full)
                              _Tag(
                                label: l10n.moveStopFull(Track.maxParallelStops),
                                icon: Icons.block_rounded,
                                active: false,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final seg in breaks)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(56, 0, 14, 6),
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined, size: 13, color: nt.danger),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l10n.segmentToWillBeDeleted(
                              _name(_arrangement.stop(seg.toStopId), l10n)),
                          style: TextStyle(fontSize: 11, color: nt.danger),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackHandle(int index, ArrangedTrack row) {
    final l10n = AppLocalizations.of(context)!;
    final picked = _picked;
    final isPicked = picked is _MovingTrack && picked.rowKey == row.key;
    final visual = _TrackNumber(number: index + 1, picked: isPicked);
    final moving = _MovingTrack(row.key);
    return Semantics(
      button: true,
      selected: isPicked,
      label: l10n.arrangeMoveTrack(index + 1),
      excludeSemantics: true,
      child: Draggable<_Moving>(
        data: moving,
        feedback: _DragProxy(
          child: _TrackProxy(
            number: index + 1,
            name: _name(row.stops.first, l10n),
            more: row.stops.length - 1,
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: visual),
        onDragStarted: () => _dragStarted(moving),
        onDragUpdate: _dragUpdated,
        onDragCompleted: _dragEnded,
        onDraggableCanceled: (_, _) => _dragEnded(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapTrack(row),
          child: visual,
        ),
      ),
    );
  }

  Widget _chip(Stop stop, ArrangedTrack row, _Moving? moving) {
    final l10n = AppLocalizations.of(context)!;
    final picked = moving is _MovingStop && moving.stopId == stop.id;
    final name = _name(stop, l10n);
    final payload = _MovingStop(stop.id);

    Widget body(Widget? handle) => _StopChip(
          name: name,
          placeType: stop.placeType,
          picked: picked,
          handle: handle,
        );
    final handle = Semantics(
      button: true,
      label: l10n.arrangeMoveStop(name),
      excludeSemantics: true,
      // Starts at once, unlike the long press on the chip itself, so dragging
      // from here never scrolls the page instead.
      child: Draggable<_Moving>(
        data: payload,
        feedback: _DragProxy(child: body(null)),
        childWhenDragging: const _HandleIcon(),
        onDragStarted: () => _dragStarted(payload),
        onDragUpdate: _dragUpdated,
        onDragCompleted: _dragEnded,
        onDraggableCanceled: (_, _) => _dragEnded(),
        child: const _HandleIcon(),
      ),
    );

    return DragTarget<_Moving>(
      // Its own stop too, and a drop leaves it be: refused, it fell through to
      // the track, which put it last.
      onWillAcceptWithDetails: (d) =>
          d.data is _MovingStop &&
          _arrangement.accepts(row.key, (d.data as _MovingStop).stopId),
      onAcceptWithDetails: (d) {
        final moving = d.data as _MovingStop;
        if (moving.stopId == stop.id) return;
        _toRow(moving, row.key, beforeStopId: stop.id);
      },
      builder: (context, candidates, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Where another dragged stop would land: before this one.
          if (candidates.any((m) => m is _MovingStop && m.stopId != stop.id))
            const _InsertMarker(),
          // Flexible: on a narrow screen the chip ellipsises its name instead
          // of overflowing the track.
          Flexible(
            child: LongPressDraggable<_Moving>(
              data: payload,
              feedback: _DragProxy(child: body(null)),
              // The chip's own size, handle and all: nothing near it moves.
              childWhenDragging:
                  Opacity(opacity: 0.35, child: body(const _HandleIcon())),
              onDragStarted: () => _dragStarted(payload),
              onDragUpdate: _dragUpdated,
              onDragCompleted: _dragEnded,
              onDraggableCanceled: (_, _) => _dragEnded(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapStop(stop, row),
                child: body(handle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _Instructions extends StatelessWidget {
  const _Instructions({required this.picked, required this.onCancel});

  /// What is picked for tap-to-place, said as a sentence; null for the hint.
  final String? picked;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final picked = this.picked;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 6, 8),
      child: picked == null
          ? Text(
              l10n.arrangeHint,
              style: TextStyle(fontSize: 13, height: 1.35, color: nt.text2),
            )
          : Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 16, color: nt.forest),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    picked,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: nt.bark,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(foregroundColor: nt.forest),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.linked});

  /// A transit link runs across this separator.
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final line = Container(height: 1, color: nt.border);
    if (!linked) return line;
    return SizedBox(
      height: 16,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Positioned.fill(child: Center(child: line)),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 34),
            child: ColoredBox(
              color: nt.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(Icons.directions_transit_rounded,
                    size: 13, color: nt.transitIcon),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GapTarget extends StatelessWidget {
  const _GapTarget({required this.hovered, required this.onTap});

  final bool hovered;

  /// Null while dragging — the drop is the gesture then.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: hovered ? nt.mist : nt.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hovered ? nt.forest : nt.canopy.withValues(alpha: 0.6),
                width: hovered ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 16, color: nt.forest),
                const SizedBox(width: 4),
                Text(
                  l10n.arrangeNewTrackHere,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: nt.forest,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackNumber extends StatelessWidget {
  const _TrackNumber({required this.number, required this.picked});

  final int number;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _HandleIcon(),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: picked ? nt.forest : nt.mist,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: picked ? nt.surface : nt.forest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandleIcon extends StatelessWidget {
  const _HandleIcon();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 2, 6),
        child: Icon(Icons.drag_indicator_rounded,
            size: 18, color: context.nt.text3),
      );
}

class _StopChip extends StatelessWidget {
  const _StopChip({
    required this.name,
    required this.placeType,
    required this.picked,
    required this.handle,
  });

  final String name;
  final PlaceType? placeType;
  final bool picked;
  final Widget? handle;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final type = placeType;
    return Semantics(
      selected: picked,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding:
            EdgeInsetsDirectional.fromSTEB(handle == null ? 10 : 0, 0, 10, 0),
        decoration: BoxDecoration(
          color: picked ? nt.mist : nt.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: picked ? nt.forest : nt.border,
            width: picked ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (handle != null) handle!,
            if (type != null) ...[
              Icon(type.icon, size: 14, color: type.color(nt)),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(vertical: handle == null ? 8 : 0),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: nt.bark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsertMarker extends StatelessWidget {
  const _InsertMarker();

  @override
  Widget build(BuildContext context) => Container(
        width: 3,
        height: 26,
        margin: const EdgeInsetsDirectional.only(end: 4),
        decoration: BoxDecoration(
          color: context.nt.forest,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.icon,
    required this.active,
  });

  final String label;
  final IconData icon;

  /// A target (forest), or a refusal (grey).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final color = active ? nt.forest : nt.text3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: active ? nt.mist : nt.border.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What follows the finger: a lifted copy on the sand accent.
class _DragProxy extends StatelessWidget {
  const _DragProxy({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Material(
      elevation: 4,
      shadowColor: nt.shadow.withValues(alpha: 0.26),
      color: nt.sand,
      borderRadius: BorderRadius.circular(999),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: child,
      ),
    );
  }
}

class _TrackProxy extends StatelessWidget {
  const _TrackProxy({
    required this.number,
    required this.name,
    required this.more,
  });

  final int number;
  final String name;

  /// The track's other alternatives, which travel with it.
  final int more;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 12, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TrackNumber(number: number, picked: true),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              more > 0 ? '$name  +$more' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: nt.bark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrokenLinksBanner extends StatelessWidget {
  const _BrokenLinksBanner({
    required this.count,
    required this.entries,
    required this.moreCount,
  });

  final int count;
  final List<String> entries;
  final int moreCount;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: nt.transitBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: nt.transitBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: nt.transitIcon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.transitSegmentsWillBeDeleted(count),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: nt.transitText,
                  ),
                ),
              ),
            ],
          ),
          for (final e in entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 24, top: 3),
              child: Text(
                '• $e',
                style: TextStyle(fontSize: 12, color: nt.transitText),
              ),
            ),
          if (moreCount > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 24, top: 3),
              child: Text(
                l10n.andMoreCount(moreCount),
                style: TextStyle(
                  fontSize: 12,
                  color: nt.transitText,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
