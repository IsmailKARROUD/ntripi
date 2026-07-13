// widgets/edit_pencil_button.dart — Soft action-blue tinted Edit affordance.
//
// kEditBlue / kEditBlueTint are RESERVED exclusively for this widget — the blue
// hue must not appear anywhere else in the app. Used for every itinerary Edit
// pencil so the Edit action reads consistently across stop cards, the stop form,
// the stop detail header, the hero overlay, and transit legs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

class EditPencilButton extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Edits can't be saved offline, so every Edit pencil self-disables (grey)
    // and explains itself on tap instead of opening a dead-end edit flow.
    final online = ref.watch(isOnlineProvider).value ?? true;
    final pill = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: online ? onTap : () => showOfflineHint(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: online ? kEditBlueTint : kBorder.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (online ? kEditBlue : kText3).withValues(alpha: 0.13)),
          ),
          child: Icon(icon, size: iconSize, color: online ? kEditBlue : kText3),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: pill) : pill;
  }
}
