// widgets/edit_pencil_button.dart — Soft action-blue tinted Edit affordance.
//
// kEditBlue / kEditBlueTint are RESERVED exclusively for this widget — the blue
// hue must not appear anywhere else in the app. Used for every itinerary Edit
// pencil so the Edit action reads consistently across stop cards, the stop form,
// the stop detail header, the hero overlay, and transit legs.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

class EditPencilButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final double iconSize;
  final String? tooltip;

  const EditPencilButton({
    super.key,
    required this.onTap,
    this.icon = Icons.edit_rounded,
    this.iconSize = 16,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: kEditBlueTint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kEditBlue.withValues(alpha: 0.13)),
          ),
          child: Icon(icon, size: iconSize, color: kEditBlue),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: pill) : pill;
  }
}
