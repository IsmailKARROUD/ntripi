// widgets/leg_tile.dart — One transport leg row inside SegmentFormScreen.
//
// Displays the leg's mode icon, summary text, and optional duration/cost
// subtitle. Edit and delete icon buttons are shown only when the callbacks
// are provided (omit them for read-only contexts).

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

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
        leg.summary,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: _subtitle(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
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
    final parts = <String>[];
    if (leg.durationMin != null) parts.add('${leg.durationMin} min');
    if (leg.isFree) {
      parts.add('Free');
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
