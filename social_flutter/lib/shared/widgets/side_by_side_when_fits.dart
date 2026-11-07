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
/// `LayoutBuilder` inside either one.
class SideBySideWhenFits extends MultiChildRenderObjectWidget {
  SideBySideWhenFits({
    super.key,
    required Widget start,
    required Widget end,
    this.spacing = 16,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  }) : super(children: [start, end]);

  /// The least room between the two when they share a row.
  final double spacing;

  /// Where the shorter of the two sits in a shared row: [CrossAxisAlignment.start],
  /// [CrossAxisAlignment.center] or [CrossAxisAlignment.end].
  final CrossAxisAlignment crossAxisAlignment;

  @override
  RenderSideBySideWhenFits createRenderObject(BuildContext context) =>
      RenderSideBySideWhenFits(
        spacing: spacing,
        crossAxisAlignment: crossAxisAlignment,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderSideBySideWhenFits renderObject) {
    renderObject
      ..spacing = spacing
      ..crossAxisAlignment = crossAxisAlignment
      ..textDirection = Directionality.of(context);
  }
}

class _SlotData extends ContainerBoxParentData<RenderBox> {}

/// The render object of [SideBySideWhenFits].
class RenderSideBySideWhenFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotData> {
  RenderSideBySideWhenFits({
    required double spacing,
    required CrossAxisAlignment crossAxisAlignment,
    required TextDirection textDirection,
  })  : _spacing = spacing,
        _crossAxisAlignment = crossAxisAlignment,
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
  RenderBox get _end => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotData) child.parentData = _SlotData();
  }

  double _naturalWidth(RenderBox child) =>
      child.getMaxIntrinsicWidth(double.infinity);

  bool _fits(double width) =>
      _naturalWidth(_start) + _spacing + _naturalWidth(_end) <=
      width + precisionErrorTolerance;

  ({Size size, bool sideBySide}) _measure(
      BoxConstraints constraints, ChildLayouter layoutChild) {
    assert(constraints.hasBoundedWidth,
        'SideBySideWhenFits needs a bounded width to decide in.');
    final width = constraints.maxWidth;
    if (_fits(width)) {
      final endWidth = _naturalWidth(_end);
      final start = layoutChild(_start,
          BoxConstraints(maxWidth: math.max(0, width - _spacing - endWidth)));
      final end = layoutChild(_end, BoxConstraints(maxWidth: endWidth));
      return (
        size: constraints
            .constrain(Size(width, math.max(start.height, end.height))),
        sideBySide: true,
      );
    }
    final fullWidth = BoxConstraints.tightFor(width: width);
    final start = layoutChild(_start, fullWidth);
    final end = layoutChild(_end, fullWidth);
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
    final startData = _start.parentData! as _SlotData;
    final endData = _end.parentData! as _SlotData;
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
    endData.offset = Offset(rtl ? 0 : size.width - _end.size.width, top(_end));
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
      _start.getMinIntrinsicWidth(height), _end.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _start.getMaxIntrinsicWidth(height) +
      _spacing +
      _end.getMaxIntrinsicWidth(height);

  double _intrinsicHeight(
      double width, double Function(RenderBox child, double width) of) {
    if (_fits(width)) {
      return math.max(of(_start, _naturalWidth(_start)),
          of(_end, _naturalWidth(_end)));
    }
    return of(_start, width) + of(_end, width);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMaxIntrinsicHeight(w));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('spacing', _spacing))
      ..add(EnumProperty('crossAxisAlignment', _crossAxisAlignment))
      ..add(FlagProperty('sideBySide',
          value: _sideBySide, ifTrue: 'side by side', ifFalse: 'stacked'));
  }
}
