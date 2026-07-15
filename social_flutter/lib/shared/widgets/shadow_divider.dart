import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

// A themed horizontal divider with a subtle downward shadow to visually
// separate content sections. Drop-in replacement for Flutter's Divider.
class ShadowDivider extends StatelessWidget {
  const ShadowDivider({
    super.key,
    this.indent = 0.0,
    this.endIndent = 0.0,
    this.height = 1.0,
  });

  final double indent;
  final double endIndent;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        boxShadow: [
          BoxShadow(
            color: context.nt.shadow.withValues(alpha: 0.125),
            blurRadius: 4,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
