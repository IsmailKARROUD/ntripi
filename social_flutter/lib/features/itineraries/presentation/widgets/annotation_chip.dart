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
  final VoidCallback? onDelete;

  const AnnotationChip({
    super.key,
    required this.annotation,
    this.onDelete,
  });

  static const _configs = {
    AnnotationType.advice: (
      icon: Icons.lightbulb_outline,
      bg: Color(0xFFE8F5E9),
      fg: Color(0xFF2E7D32),
      label: 'Advice',
    ),
    AnnotationType.caution: (
      icon: Icons.warning_amber_outlined,
      bg: Color(0xFFFFF3E0),
      fg: Color(0xFFE65100),
      label: 'Caution',
    ),
    AnnotationType.avoid: (
      icon: Icons.block,
      bg: Color(0xFFFFEBEE),
      fg: Color(0xFFC62828),
      label: 'Avoid',
    ),
    AnnotationType.info: (
      icon: Icons.info_outline,
      bg: Color(0xFFE3F2FD),
      fg: Color(0xFF1565C0),
      label: 'Info',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final config = _configs[annotation.type]!;

    return Chip(
      backgroundColor: config.bg,
      side: BorderSide.none,
      avatar: Icon(config.icon, size: 16, color: config.fg),
      label: Text(
        annotation.content,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: config.fg, fontSize: 12),
      ),
      deleteIcon: onDelete != null
          ? Icon(Icons.close, size: 14, color: config.fg)
          : null,
      onDeleted: onDelete,
      visualDensity: VisualDensity.compact,
    );
  }
}
