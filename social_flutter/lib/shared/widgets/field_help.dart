// shared/widgets/field_help.dart — Help "?" icon + label widget for form fields.
//
// Adds a small `?` button next to a field label. Tapping it pops a compact
// notification card out of the icon explaining the field's purpose. Tap
// anywhere outside the card to dismiss. Used uniformly across every form
// in the app so users learn the affordance once.

import 'package:flutter/material.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Small circular "?" icon button. Tapping it opens a popover positioned
/// next to the icon with the given [helpTitle] and [helpMessage]. Wrapped
/// in a [Tooltip] so hover (web/desktop) and long-press (mobile) reveal
/// the field name.
class FieldHelpIcon extends StatelessWidget {
  final String helpTitle;
  final String helpMessage;
  final Color? color;
  final double size;

  const FieldHelpIcon({
    super.key,
    required this.helpTitle,
    required this.helpMessage,
    this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).hintColor.withValues(alpha: 0.8);
    return Tooltip(
      message: helpTitle,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Builder(
          // Builder gives the IconButton its own BuildContext so we can
          // resolve the icon's RenderBox at tap time and anchor the popover.
          builder: (innerCtx) => IconButton(
            padding: EdgeInsets.zero,
            iconSize: size,
            splashRadius: size,
            tooltip: AppLocalizations.of(innerCtx)!.fieldHelpTooltip,
            icon: Icon(Icons.help_outline, color: effectiveColor),
            onPressed: () => showFieldHelp(
              innerCtx,
              title: helpTitle,
              message: helpMessage,
            ),
          ),
        ),
      ),
    );
  }
}

/// A label that renders as `Text + ?` in a row. Designed for two use cases:
///   1. Pass directly to `InputDecoration(label: LabelWithHelp(...))` — Flutter
///      will style/animate it like a normal floating label.
///   2. Use as a standalone label above non-TextField widgets (Switch,
///      SegmentedButton, custom inputs).
///
/// When [labelStyle] is omitted, [LabelWithHelp] inherits the surrounding
/// `InputDecoration` text style (so it floats and recolors like a stock label).
class LabelWithHelp extends StatelessWidget {
  final String label;
  final String helpTitle;
  final String helpMessage;
  final TextStyle? labelStyle;
  final double iconSize;

  const LabelWithHelp({
    super.key,
    required this.label,
    required this.helpTitle,
    required this.helpMessage,
    this.labelStyle,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(label, style: labelStyle, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 2),
        FieldHelpIcon(
          helpTitle: helpTitle,
          helpMessage: helpMessage,
          size: iconSize,
        ),
      ],
    );
  }
}

/// Shows a compact help popover anchored to the widget that owns [context]
/// (typically the `?` icon button). Tap anywhere outside the popover to
/// dismiss it.
void showFieldHelp(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return;

  final mediaQuery = MediaQuery.of(context);
  final screenSize = mediaQuery.size;
  final safePadding = mediaQuery.padding;
  final theme = Theme.of(context);

  final iconTopLeft = renderObject.localToGlobal(Offset.zero);
  final iconSize = renderObject.size;
  final iconCenterX = iconTopLeft.dx + iconSize.width / 2;
  final iconBottomY = iconTopLeft.dy + iconSize.height;

  const popoverMaxWidth = 280.0;
  const horizontalMargin = 12.0;
  const verticalGap = 6.0;
  // Rough estimate; only used to decide above vs below.
  const estimatedPopoverHeight = 120.0;

  final availableWidth = screenSize.width - 2 * horizontalMargin;
  final popoverWidth =
      availableWidth < popoverMaxWidth ? availableWidth : popoverMaxWidth;

  // Center on the icon, then clamp to the screen.
  double left = iconCenterX - popoverWidth / 2;
  final maxLeft = screenSize.width - popoverWidth - horizontalMargin;
  if (left < horizontalMargin) left = horizontalMargin;
  if (left > maxLeft) left = maxLeft;

  final spaceBelow =
      screenSize.height - safePadding.bottom - iconBottomY - verticalGap;
  final showAbove = spaceBelow < estimatedPopoverHeight;

  final double? top = showAbove ? null : iconBottomY + verticalGap;
  final double? bottom = showAbove
      ? screenSize.height - iconTopLeft.dy + verticalGap
      : null;

  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  bool dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: dismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: popoverWidth,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                alignment:
                    showAbove ? Alignment.bottomCenter : Alignment.topCenter,
                child: child,
              ),
            ),
            child: _FieldHelpCard(
              title: title,
              message: message,
              theme: theme,
              onClose: dismiss,
            ),
          ),
        ),
      ],
    ),
  );

  overlay.insert(entry);
}

class _FieldHelpCard extends StatelessWidget {
  final String title;
  final String message;
  final ThemeData theme;
  final VoidCallback onClose;

  const _FieldHelpCard({
    required this.title,
    required this.message,
    required this.theme,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Material(
      type: MaterialType.card,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: cs.surface,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.help_outline, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            InkResponse(
              onTap: onClose,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: cs.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
