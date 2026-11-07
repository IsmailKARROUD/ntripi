// shared/widgets/side_by_side_when_fits.dart — "in one row, unless there is no
// room": two pieces a phone stacks sit side by side once the box is wide
// enough for both. The children measure themselves — their own style, text
// scaler and bold-text setting — so the answer holds in every language and at
// every text size, where a breakpoint or a TextPainter would only guess.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [start] and [end] side by side when both fit at their natural widths
/// with [spacing] between them — [start] against the start edge, [end] against
/// the end edge — and otherwise stacks them, [start] above [end], each as wide
/// as the box: the phone layout.
///
/// Decided at every layout from each child's max intrinsic width, so it
/// follows a resize live. A child must therefore answer intrinsic sizes: no
/// `LayoutBuilder` inside one.
///
/// [stackedEnd], when given, stands below [start] in place of [end] — for a
/// piece whose phone form differs from its form in a shared row.
class SideBySideWhenFits extends MultiChildRenderObjectWidget {
  SideBySideWhenFits({
    super.key,
    required Widget start,
    required Widget end,
    Widget? stackedEnd,
    this.spacing = 16,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.expandEnd = false,
  }) : super(children: [start, end, if (stackedEnd != null) stackedEnd]);

  /// The least room between the two when they share a row.
  final double spacing;

  /// Where the shorter of the two sits in a shared row: [CrossAxisAlignment.start],
  /// [CrossAxisAlignment.center] or [CrossAxisAlignment.end].
  final CrossAxisAlignment crossAxisAlignment;

  /// Whether, in a shared row, `end` takes all the room `start` leaves — to
  /// spread its own pieces out — rather than its natural width.
  final bool expandEnd;

  @override
  RenderSideBySideWhenFits createRenderObject(BuildContext context) =>
      RenderSideBySideWhenFits(
        spacing: spacing,
        crossAxisAlignment: crossAxisAlignment,
        expandEnd: expandEnd,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderSideBySideWhenFits renderObject) {
    renderObject
      ..spacing = spacing
      ..crossAxisAlignment = crossAxisAlignment
      ..expandEnd = expandEnd
      ..textDirection = Directionality.of(context);
  }
}

class _SlotData extends ContainerBoxParentData<RenderBox> {}

/// The render object of [SideBySideWhenFits]. Its children are the start
/// piece, the end piece and, when given, the stacked end piece — which stands
/// below the start piece in place of the end piece when the two do not fit.
/// Both end pieces stay built; only the one the layout picks is painted, hit
/// and read out, so neither may hold a control that takes keyboard focus.
class RenderSideBySideWhenFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotData> {
  RenderSideBySideWhenFits({
    required double spacing,
    required CrossAxisAlignment crossAxisAlignment,
    required bool expandEnd,
    required TextDirection textDirection,
  })  : _spacing = spacing,
        _crossAxisAlignment = crossAxisAlignment,
        _expandEnd = expandEnd,
        _textDirection = textDirection;

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  CrossAxisAlignment _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment value) {
    if (value == _crossAxisAlignment) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  bool _expandEnd;
  set expandEnd(bool value) {
    if (value == _expandEnd) return;
    _expandEnd = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Whether the last layout put the two side by side.
  bool get sideBySide => _sideBySide;
  bool _sideBySide = false;

  RenderBox get _start => firstChild!;
  RenderBox get _end => childAfter(_start)!;
  RenderBox? get _stackedEnd => childAfter(_end);

  /// What stands below the start piece when the two do not fit.
  RenderBox get _endWhenStacked => _stackedEnd ?? _end;

  /// The end piece the last layout shows.
  RenderBox get _shownEnd => _sideBySide ? _end : _endWhenStacked;

  /// The end piece the last layout keeps out of sight, if there are two.
  RenderBox? get _hiddenEnd =>
      _stackedEnd == null ? null : (_sideBySide ? _stackedEnd : _end);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotData) child.parentData = _SlotData();
  }

  double _naturalWidth(RenderBox child) =>
      child.getMaxIntrinsicWidth(double.infinity);

  bool _fits(double width) =>
      _naturalWidth(_start) + _spacing + _naturalWidth(_end) <=
      width + precisionErrorTolerance;

  /// The constraints each piece gets in a shared row [width] wide.
  ({BoxConstraints start, BoxConstraints end}) _sharedRow(double width) {
    final startWidth = _naturalWidth(_start);
    final endWidth = _naturalWidth(_end);
    return _expandEnd
        ? (
            start: BoxConstraints(maxWidth: startWidth),
            end: BoxConstraints.tightFor(
                width: math.max(0, width - _spacing - startWidth)),
          )
        : (
            start: BoxConstraints(
                maxWidth: math.max(0, width - _spacing - endWidth)),
            end: BoxConstraints(maxWidth: endWidth),
          );
  }

  ({Size size, bool sideBySide}) _measure(
      BoxConstraints constraints, ChildLayouter layoutChild) {
    assert(constraints.hasBoundedWidth,
        'SideBySideWhenFits needs a bounded width to decide in.');
    final width = constraints.maxWidth;
    if (_fits(width)) {
      final row = _sharedRow(width);
      final start = layoutChild(_start, row.start);
      final end = layoutChild(_end, row.end);
      return (
        size: constraints
            .constrain(Size(width, math.max(start.height, end.height))),
        sideBySide: true,
      );
    }
    final fullWidth = BoxConstraints.tightFor(width: width);
    final start = layoutChild(_start, fullWidth);
    final end = layoutChild(_endWhenStacked, fullWidth);
    return (
      size: constraints.constrain(Size(width, start.height + end.height)),
      sideBySide: false,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _measure(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  void performLayout() {
    final result = _measure(constraints, ChildLayoutHelper.layoutChild);
    size = result.size;
    _sideBySide = result.sideBySide;
    // Laid out like Offstage's child, so it is ready the moment it is picked.
    _hiddenEnd?.layout(BoxConstraints(maxWidth: size.width));

    final startData = _start.parentData! as _SlotData;
    final endData = _shownEnd.parentData! as _SlotData;
    if (!_sideBySide) {
      startData.offset = Offset.zero;
      endData.offset = Offset(0, _start.size.height);
      return;
    }
    double top(RenderBox child) => switch (_crossAxisAlignment) {
          CrossAxisAlignment.start => 0,
          CrossAxisAlignment.end => size.height - child.size.height,
          _ => (size.height - child.size.height) / 2,
        };
    final rtl = _textDirection == TextDirection.rtl;
    startData.offset =
        Offset(rtl ? size.width - _start.size.width : 0, top(_start));
    endData.offset =
        Offset(rtl ? 0 : size.width - _end.size.width, top(_end));
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
      _start.getMinIntrinsicWidth(height),
      _endWhenStacked.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _start.getMaxIntrinsicWidth(height) +
      _spacing +
      _end.getMaxIntrinsicWidth(height);

  double _intrinsicHeight(
      double width, double Function(RenderBox child, double width) of) {
    if (_fits(width)) {
      final startWidth = _naturalWidth(_start);
      final endWidth =
          _expandEnd ? width - _spacing - startWidth : _naturalWidth(_end);
      return math.max(of(_start, startWidth), of(_end, endWidth));
    }
    return of(_start, width) + of(_endWhenStacked, width);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMaxIntrinsicHeight(w));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final distance = _start.getDistanceToActualBaseline(baseline);
    return distance == null
        ? null
        : distance + (_start.parentData! as _SlotData).offset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in [_start, _shownEnd]) {
      context.paintChild(
          child, (child.parentData! as _SlotData).offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_shownEnd, _start]) {
      final hit = result.addWithPaintOffset(
        offset: (child.parentData! as _SlotData).offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(_start);
    visitor(_shownEnd);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('spacing', _spacing))
      ..add(EnumProperty('crossAxisAlignment', _crossAxisAlignment))
      ..add(FlagProperty('expandEnd', value: _expandEnd, ifTrue: 'expand end'))
      ..add(FlagProperty('sideBySide',
          value: _sideBySide, ifTrue: 'side by side', ifFalse: 'stacked'));
  }
}
