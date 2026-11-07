// shared/widgets/content_column.dart — how a screen takes the one width rule
// (core/ui/app_layout.dart): its content, or its whole page, in a centred
// column never wider than kContentMaxWidth.

import 'package:flutter/widgets.dart';
import 'package:ntripi/core/ui/app_theme.dart';

/// A screen's content, centred and never wider than [kContentMaxWidth].
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
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: child,
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
