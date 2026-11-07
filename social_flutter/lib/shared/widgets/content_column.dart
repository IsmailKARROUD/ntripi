// shared/widgets/content_column.dart — how a screen takes the one width rule
// (core/ui/app_layout.dart): its content, or its whole page, in a centred
// column never wider than kContentMaxWidth.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';

/// How much of the window the tabs' side bar takes at this screen's start edge
/// — 0 outside the tabs' shell, and while the tabs are along the bottom.
///
/// The shell gives its tabs the whole window but the bar, so a tab reaches the
/// window's far edge; the column leaves the bar's width free at its own end,
/// which keeps it centred on the window — where a page without the bar puts it.
class SideBarInset extends InheritedWidget {
  const SideBarInset({super.key, required this.width, required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideBarInset>()?.width ?? 0;

  @override
  bool updateShouldNotify(SideBarInset oldWidget) => width != oldWidget.width;
}

/// The room on either side of the column in a box [boxWidth] wide whose start
/// edge sits [inset] past the window's (see [SideBarInset]), measured from the
/// box's own edges.
({double start, double end}) columnGaps(double boxWidth, double inset) {
  final side = math.max(0.0, (boxWidth - inset - kContentMaxWidth) / 2);
  return (start: side, end: side + inset);
}

/// A screen's content, centred on the window and never wider than
/// [kContentMaxWidth].
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    this.alignment = Alignment.center,
    required this.child,
  });

  /// Where the column sits when the content is shorter than the screen.
  final AlignmentGeometry alignment;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        // Always a Padding, zero or not: a resize across the side bar's line
        // must not change the tree, or the screen below would be rebuilt.
        padding: EdgeInsetsDirectional.only(end: SideBarInset.of(context)),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: child,
          ),
        ),
      );
}

/// A whole page in the column — for a Scaffold whose own slots carry chrome
/// (an AppBar, a floating button), which a [ContentColumn] around the body
/// would leave spanning the window.
class ContentPage extends StatelessWidget {
  const ContentPage({super.key, required this.child});

  /// The page's Scaffold.
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        // A route paints its whole window: nothing below it fills the sides.
        color: context.nt.surface,
        child: ContentColumn(child: child),
      );
}

/// A sliver held to the column — for a scroll view that spans the screen
/// because something in it is allowed to be wider than the column.
class SliverContentColumn extends StatelessWidget {
  const SliverContentColumn({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    final inset = SideBarInset.of(context);
    return SliverLayoutBuilder(builder: (context, constraints) {
      final gaps = columnGaps(constraints.crossAxisExtent, inset);
      return SliverPadding(
        padding: EdgeInsetsDirectional.only(start: gaps.start, end: gaps.end),
        sliver: sliver,
      );
    });
  }
}

/// The floating button of a Scaffold that spans the screen while its content
/// keeps to the column: in the screen's far corner when the room beside the
/// column holds it, otherwise at the column's own corner — over the content,
/// as on a phone.
class ColumnFabLocation extends StandardFabLocation with FabFloatOffsetY {
  const ColumnFabLocation([this.inset = 0]);

  /// The [SideBarInset] where the Scaffold sits.
  final double inset;

  @override
  double getOffsetX(ScaffoldPrelayoutGeometry geometry, double adjustment) {
    const margin = kFloatingActionButtonMargin;
    final width = geometry.scaffoldSize.width;
    final button = geometry.floatingActionButtonSize.width;
    final rtl = geometry.textDirection == TextDirection.rtl;
    final safeEnd = rtl ? geometry.minInsets.left : geometry.minInsets.right;
    final besideColumn = columnGaps(width, inset).end;
    // Distance from the end edge: the screen's corner when the button clears
    // the column there, else the column's corner, never inside the safe area.
    final fromEnd = besideColumn >= button + 2 * margin + safeEnd
        ? margin + safeEnd
        : math.max(besideColumn + margin, margin + safeEnd);
    return rtl ? fromEnd - adjustment : width - fromEnd - button + adjustment;
  }

  @override
  bool operator ==(Object other) =>
      other is ColumnFabLocation && other.inset == inset;

  @override
  int get hashCode => inset.hashCode;

  @override
  String toString() => 'ColumnFabLocation($inset)';
}
