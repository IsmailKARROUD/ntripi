// widgets/stop_card.dart — Card representing one stop in the detail list.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';

class StopCard extends StatelessWidget {
  final Stop stop;
  final String currency;

  /// 1-based display index (track number). If null, the type icon is shown instead.
  final int? trackIndex;

  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onAddAnnotation;
  final void Function(Annotation)? onEditAnnotation;
  final void Function(Annotation)? onDeleteAnnotation;

  const StopCard({
    super.key,
    required this.stop,
    required this.currency,
    this.trackIndex,
    this.onTap,
    this.onEdit,
    this.onAddAnnotation,
    this.onEditAnnotation,
    this.onDeleteAnnotation,
  });

  static const _typeIcons = {
    StopType.origin: Icons.trip_origin,
    StopType.waypoint: Icons.place_outlined,
    StopType.arrival: Icons.flag,
  };

  static const _typeColors = {
    StopType.origin: Colors.green,
    StopType.waypoint: Colors.blue,
    StopType.arrival: Colors.red,
  };

  String _formatCost(double cost, bool isFree, String currency) {
    if (isFree) return 'Free';
    if (cost <= 0.0) return '';
    return '${cost.toStringAsFixed(2)} $currency';
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColors[stop.type] ?? Colors.blue;
    final typeIcon = _typeIcons[stop.type] ?? Icons.place;
    final costLabel = _formatCost(stop.cost, stop.isFree, currency);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Position + type icon column
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: typeColor.withOpacity(0.15),
                      child: trackIndex != null
                          ? Text(
                              '$trackIndex',
                              style: TextStyle(
                                color: typeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            )
                          : Icon(
                              _typeIcons[stop.type] ?? Icons.place_outlined,
                              color: typeColor,
                              size: 14,
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stop.placeName ??
                            stop.type.name[0].toUpperCase() +
                                stop.type.name.substring(1),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
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

                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),

            if (stop.annotations.isNotEmpty || onAddAnnotation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 40),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...stop.annotations.map(
                      (a) => AnnotationChip(
                        annotation: a,
                        onEdit: onEditAnnotation != null
                            ? () => onEditAnnotation!(a)
                            : null,
                        onDelete: onDeleteAnnotation != null
                            ? () => onDeleteAnnotation!(a)
                            : null,
                      ),
                    ),
                    if (onAddAnnotation != null)
                      GestureDetector(
                        onTap: onAddAnnotation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.grey.shade300,
                                style: BorderStyle.solid),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 13,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(
                                'Add note',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

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
