// widgets/annotation_chip.dart — Colored chip for a stop annotation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

/// Displays an annotation as a compact colored chip.
///
/// Colors convey intent at a glance:
///   advice  → green   (positive tip)
///   caution → orange  (be aware)
///   avoid   → red     (stay away)
///   info    → blue    (neutral)
class AnnotationChip extends ConsumerWidget {
  final Annotation annotation;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Long-press to report this note. Null for the author and in edit mode.
  /// Deliberately without a visible affordance — a flag glyph on a chip this
  /// small would cost more of the text than it is worth.
  final VoidCallback? onReport;

  const AnnotationChip({
    super.key,
    required this.annotation,
    this.onEdit,
    this.onDelete,
    this.onReport,
  });

  // Compact outline-icon variant; colors come from the shared editorial
  // pairs on NtripiColors so the chip follows the theme.
  static const _icons = {
    AnnotationType.advice: Icons.lightbulb_outline,
    AnnotationType.caution: Icons.warning_amber_outlined,
    AnnotationType.avoid: Icons.block,
    AnnotationType.info: Icons.info_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final config = (
      icon: _icons[annotation.type]!,
      bg: annotation.type.bg(nt),
      fg: annotation.type.fg(nt),
    );
    // Edit/delete are mutations — offline the taps explain instead of firing.
    final online = ref.watch(isOnlineProvider).value ?? true;
    final VoidCallback? editTap =
        online ? onEdit : (onEdit != null ? () => showOfflineHint(context) : null);
    final VoidCallback? deleteTap = online
        ? onDelete
        : (onDelete != null ? () => showOfflineHint(context) : null);

    final textWidget = Text(
      annotation.content,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: config.fg, fontSize: 14),
    );
    // The inner detectors only claim taps, so the long-press reaches this one.
    return GestureDetector(
      onLongPress: onReport,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: config.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 16, color: config.fg),
            const SizedBox(width: 4),
            if (onEdit != null)
              Flexible(
                child: GestureDetector(
                  onTap: editTap,
                  child: textWidget,
                ),
              )
            else
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: textWidget,
                ),
              ),
            if (onEdit != null) ...[
              const SizedBox(width: 2),
              GestureDetector(
                onTap: editTap,
                child: Icon(Icons.edit_outlined, size: 16, color: config.fg),
              ),
            ],
            if (onDelete != null)
              GestureDetector(
                onTap: deleteTap,
                child: Icon(Icons.close, size: 18, color: config.fg),
              ),
          ],
        ),
      ),
    );
  }
}
