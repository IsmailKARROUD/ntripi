// widgets/segment_card.dart — Card showing a transit segment between two stops.
//
// Rendered inside buildInterleavedList() in itinerary_detail_screen.dart.
// The horizontal padding (36) intentionally indents it relative to StopCards
// so it looks visually nested between them.
// onEdit / onDelete are null in read-only mode; non-null in edit mode.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/transport_badge.dart';

class SegmentCard extends StatelessWidget {
  final TransitSegment segment;
  final String currency;
  final String? fromStopName;
  final String? toStopName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SegmentCard({
    super.key,
    required this.segment,
    required this.currency,
    this.fromStopName,
    this.toStopName,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_transit_outlined,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${fromStopName ?? '?'} → ${toStopName ?? '?'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: onEdit,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.orange.shade700,
                    ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.red.shade400,
                    ),
                  ],
                ],
              ),
              if (segment.legs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children:
                      segment.legs.map((leg) => TransportBadge(leg: leg)).toList(),
                ),
              ],
              if (segment.totalDurationMin > 0 || segment.totalCost > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (segment.totalDurationMin > 0) ...[
                      Icon(Icons.timer_outlined,
                          size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 3),
                      Text(
                        segment.formattedDuration,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (segment.totalCost > 0) ...[
                      Icon(Icons.euro_symbol,
                          size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 3),
                      Text(
                        segment.formattedCost(currency),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
