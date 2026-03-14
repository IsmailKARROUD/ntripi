// widgets/stop_card.dart — Card representing one stop in the detail list.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/transport_badge.dart';

/// Displays a stop with its position, type, location, cost/duration chips,
/// transport info (if transit), and annotation chips.
///
/// [onEdit] and [onDelete] are called when the user taps the action icons.
class StopCard extends StatelessWidget {
  final Stop stop;
  final String currency;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const StopCard({
    super.key,
    required this.stop,
    required this.currency,
    this.onEdit,
    this.onDelete,
  });

  static const _typeIcons = {
    StopType.origin: Icons.trip_origin,
    StopType.waypoint: Icons.place_outlined,
    StopType.transit: Icons.directions_transit,
    StopType.destination: Icons.flag,
  };

  static const _typeColors = {
    StopType.origin: Colors.green,
    StopType.waypoint: Colors.blue,
    StopType.transit: Colors.grey,
    StopType.destination: Colors.red,
  };

  String _formatCost(double cost, bool isFree, String currency) {
    if (isFree) return 'Free';
    if (cost <= 0.0) return '';
    return '${cost.toStringAsFixed(2)} $currency';
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColors[stop.type] ?? Colors.grey;
    final typeIcon = _typeIcons[stop.type] ?? Icons.place;
    final costLabel = _formatCost(stop.cost, stop.isFree, currency);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Position + type icon column
                Column(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: typeColor.withOpacity(0.15),
                      child: Text(
                        '${stop.position}',
                        style: TextStyle(
                          color: typeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(typeIcon, size: 16, color: typeColor),
                  ],
                ),
                const SizedBox(width: 12),

                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Place name
                      Text(
                        stop.placeName ??
                            stop.type.name[0].toUpperCase() +
                                stop.type.name.substring(1),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),

                      // Address (if set)
                      if (stop.placeAddress != null &&
                          stop.placeAddress!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            stop.placeAddress!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      // Transit badge
                      if (stop.type == StopType.transit)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TransportBadge(stop: stop),
                        ),

                      // Duration + cost chips
                      if (stop.durationMin != null || costLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            children: [
                              if (stop.durationMin != null)
                                _InfoChip(
                                  icon: Icons.timer_outlined,
                                  label: '${stop.durationMin} min',
                                ),
                              if (costLabel.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.euro_symbol,
                                  label: costLabel,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Edit + delete icons
                Column(
                  children: [
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.red.shade400,
                      ),
                  ],
                ),
              ],
            ),

            // Annotation chips
            if (stop.annotations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 40),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: stop.annotations
                      .map((a) => AnnotationChip(annotation: a))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small chip used for duration and cost info inside a stop card.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade700, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
