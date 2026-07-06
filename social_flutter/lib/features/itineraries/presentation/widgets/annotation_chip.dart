// widgets/annotation_chip.dart — Colored chip for a stop annotation.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';

/// Displays an annotation as a compact colored chip.
///
/// Colors convey intent at a glance:
///   advice  → green   (positive tip)
///   caution → orange  (be aware)
///   avoid   → red     (stay away)
///   info    → blue    (neutral)
class AnnotationChip extends StatelessWidget {
  final Annotation annotation;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const AnnotationChip({
    super.key,
    required this.annotation,
    this.onEdit,
    this.onDelete,
  });

  // Compact outline-icon variant — intentionally lighter than the editorial
  // palette on AnnotationType itself; type names come from type.label(l10n).
  static const _configs = {
    AnnotationType.advice: (
      icon: Icons.lightbulb_outline,
      bg: Color(0xFFE8F5E9),
      fg: Color(0xFF2E7D32),
    ),
    AnnotationType.caution: (
      icon: Icons.warning_amber_outlined,
      bg: Color(0xFFFFF3E0),
      fg: Color(0xFFE65100),
    ),
    AnnotationType.avoid: (
      icon: Icons.block,
      bg: Color(0xFFFFEBEE),
      fg: Color(0xFFC62828),
    ),
    AnnotationType.info: (
      icon: Icons.info_outline,
      bg: Color(0xFFE3F2FD),
      fg: Color(0xFF1565C0),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final config = _configs[annotation.type]!;

    final textWidget = Text(
      annotation.content,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: config.fg, fontSize: 14),
    );
    return Container(
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
                onTap: onEdit,
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
              onTap: onEdit,
              child: Icon(Icons.edit_outlined, size: 16, color: config.fg),
            ),
          ],
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close, size: 18, color: config.fg),
            ),
        ],
      ),
    );
  }
}
