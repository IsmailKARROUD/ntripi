// widgets/transport_badge.dart — Badge showing transit mode + line + direction.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';

/// Compact badge shown on transit stops inside a StopCard.
///
/// Example output: 🚋 Tram 3 → direction Nation
/// If no line or direction is set, just the mode icon is shown.
class TransportBadge extends StatelessWidget {
  final Stop stop;

  const TransportBadge({super.key, required this.stop});

  static const _modeLabels = {
    TransportMode.walk: ('🚶', 'Walk'),
    TransportMode.bus: ('🚌', 'Bus'),
    TransportMode.tram: ('🚋', 'Tram'),
    TransportMode.metro: ('🚇', 'Metro'),
    TransportMode.train: ('🚆', 'Train'),
    TransportMode.taxi: ('🚕', 'Taxi'),
    TransportMode.uber: ('🚗', 'Uber'),
    TransportMode.bike: ('🚲', 'Bike'),
    TransportMode.ferry: ('⛴', 'Ferry'),
    TransportMode.car: ('🚗', 'Car'),
  };

  @override
  Widget build(BuildContext context) {
    final mode = stop.transportMode;
    final (emoji, label) = mode != null
        ? _modeLabels[mode] ?? ('🚌', mode.name)
        : ('🚌', 'Transit');

    final parts = <String>[
      '$emoji $label',
      if (stop.transportLine != null && stop.transportLine!.isNotEmpty)
        stop.transportLine!,
      if (stop.transportDirection != null &&
          stop.transportDirection!.isNotEmpty)
        '→ ${stop.transportDirection}',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        parts.join(' '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
