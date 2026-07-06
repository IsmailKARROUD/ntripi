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
///
/// Set [pointer] to draw a small beak on the card that visually points at the
/// anchor widget — used when the anchor is a real action button (e.g. the Edit
/// pencil) rather than a `?` icon sitting right next to its label.
void showFieldHelp(
  BuildContext context, {
  required String title,
  required String message,
  bool pointer = false,
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

  // Tuck the card closer to the anchor when a beak bridges the gap.
  final gap = pointer ? 3.0 : verticalGap;
  final double? top = showAbove ? null : iconBottomY + gap;
  final double? bottom =
      showAbove ? screenSize.height - iconTopLeft.dy + gap : null;

  // Horizontal offset of the beak inside the card so its tip sits under the
  // anchor's center (clamped so it stays within the card's rounded corners).
  const beakWidth = 18.0;
  final beakLeft = (iconCenterX - left - beakWidth / 2)
      .clamp(14.0, popoverWidth - beakWidth - 14.0);

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
            child: pointer
                ? _PointerPopover(
                    pointingUp: !showAbove,
                    beakLeft: beakLeft,
                    beakWidth: beakWidth,
                    fill: theme.colorScheme.surface,
                    border: theme.colorScheme.outlineVariant,
                    card: _FieldHelpCard(
                      title: title,
                      message: message,
                      theme: theme,
                      onClose: dismiss,
                    ),
                  )
                : _FieldHelpCard(
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
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
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

/// Stacks a help [card] with a small triangular beak so the popover visibly
/// points at its anchor. The beak sits above the card ([pointingUp]) or below
/// it, offset by [beakLeft] so its tip lines up under the anchor's center.
class _PointerPopover extends StatelessWidget {
  final Widget card;
  final bool pointingUp;
  final double beakLeft;
  final double beakWidth;
  final Color fill;
  final Color border;

  const _PointerPopover({
    required this.card,
    required this.pointingUp,
    required this.beakLeft,
    required this.beakWidth,
    required this.fill,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    const beakHeight = 9.0;
    final beak = Positioned(
      left: beakLeft,
      top: pointingUp ? 0 : null,
      bottom: pointingUp ? null : 0,
      child: CustomPaint(
        size: Size(beakWidth, beakHeight),
        painter: _BeakPainter(pointingUp: pointingUp, fill: fill, border: border),
      ),
    );
    // Card overlaps the beak base by 1px, and the beak is painted last (on top),
    // so its fill hides the card's border where they meet — no seam line.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: pointingUp ? beakHeight - 1 : 0,
            bottom: pointingUp ? 0 : beakHeight - 1,
          ),
          child: card,
        ),
        beak,
      ],
    );
  }
}

/// Draws a triangle whose apex points toward the anchor. Only the two slanted
/// edges are stroked (the base is left open) so the beak merges into the card.
class _BeakPainter extends CustomPainter {
  final bool pointingUp;
  final Color fill;
  final Color border;

  _BeakPainter({
    required this.pointingUp,
    required this.fill,
    required this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (pointingUp) {
      path.moveTo(0, h);
      path.lineTo(w / 2, 0);
      path.lineTo(w, h);
    } else {
      path.moveTo(0, 0);
      path.lineTo(w / 2, h);
      path.lineTo(w, 0);
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BeakPainter old) =>
      old.pointingUp != pointingUp ||
      old.fill != fill ||
      old.border != border;
}
