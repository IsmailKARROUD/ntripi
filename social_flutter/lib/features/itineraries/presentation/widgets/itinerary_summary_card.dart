// widgets/itinerary_summary_card.dart — Shared card used on list and profile screens.
//
// Displays title, visibility badge, and summary stats (duration, cost, stops,
// safety rating). Tapping navigates to the itinerary detail screen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';

class ItinerarySummaryCard extends StatelessWidget {
  final Itinerary itinerary;

  /// Optional long-press callback (e.g. for delete confirmation).
  final VoidCallback? onLongPress;

  const ItinerarySummaryCard({
    super.key,
    required this.itinerary,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/itineraries/${itinerary.id}'),
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + visibility badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      itinerary.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  _VisibilityBadge(itinerary: itinerary),
                ],
              ),
              const SizedBox(height: 10),

              // Stats row
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _Stat(
                    icon: Icons.timer_outlined,
                    label: itinerary.formattedDuration,
                  ),
                  _Stat(
                    icon: Icons.payments_outlined,
                    label: itinerary.formattedCost,
                  ),
                  _Stat(
                    icon: Icons.place_outlined,
                    label:
                        '${itinerary.stops.length} stop${itinerary.stops.length == 1 ? '' : 's'}',
                  ),
                  if (itinerary.safetyRating != null)
                    _Stat(
                      icon: Icons.star,
                      label: '${itinerary.safetyRating}/5',
                      iconColor: Colors.amber,
                    ),
                  if (itinerary.ratingAvg != null)
                    _Stat(
                      icon: Icons.star_rounded,
                      label:
                          '${itinerary.ratingAvg!.toStringAsFixed(1)} (${itinerary.ratingCount})',
                      iconColor: Colors.orange,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  final Itinerary itinerary;

  const _VisibilityBadge({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            itinerary.visibilityIcon,
            size: 12,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            itinerary.visibilityLabel,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const _Stat({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
      ],
    );
  }
}
