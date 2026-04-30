// widgets/transport_badge.dart — Compact badge showing a transport leg's mode + line + direction.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

/// Compact badge shown in a SegmentCard or leg list.
/// Example: "Tram · 3 → direction Nation"
class TransportBadge extends StatelessWidget {
  final TransportLeg leg;

  const TransportBadge({super.key, required this.leg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(leg.mode.icon, size: 13, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            leg.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
