// widgets/leg_tile.dart — One transport leg row inside SegmentFormScreen.
//
// Displays the leg's mode icon, summary text, and optional duration/cost
// subtitle. Edit and delete icon buttons are shown only when the callbacks
// are provided (omit them for read-only contexts).

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class LegTile extends StatelessWidget {
  final TransportLeg leg;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const LegTile({
    super.key,
    required this.leg,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: Colors.blue.shade50,
        child: Icon(leg.mode.icon, size: 14, color: Colors.blue.shade700),
      ),
      title: Text(
        leg.summary(AppLocalizations.of(context)!),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: _subtitle(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            EditPencilButton(
              onTap: onEdit,
              icon: Icons.edit_outlined,
              iconSize: 18,
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              color: Colors.red.shade400,
            ),
        ],
      ),
    );
  }

  Widget? _subtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[];
    if (leg.durationMin != null) {
      parts.add('${leg.durationMin} ${l10n.minutesLabel}');
    }
    if (leg.isFree) {
      parts.add(l10n.freeLegLabel);
    } else if (leg.cost > 0) {
      parts.add(leg.cost.toStringAsFixed(2));
    }
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Colors.grey.shade600),
    );
  }
}
