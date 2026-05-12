// widgets/itinerary_summary_card.dart — Shared card used on list and profile screens.
//
// Displays title, visibility badge, and summary stats (duration, cost, stops,
// safety rating). Tapping navigates to the itinerary detail screen.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class ItinerarySummaryCard extends ConsumerWidget {
  final Itinerary itinerary;

  /// Optional long-press callback (e.g. for delete confirmation).
  final VoidCallback? onLongPress;

  const ItinerarySummaryCard({
    super.key,
    required this.itinerary,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias, // This forces the child to follow the shape
      child: InkWell(
        onTap: () => context.push('/itineraries/${itinerary.id}'),
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: AlignmentDirectional.bottomStart,
          children: [
            // Cover image thumbnail — shown only when the itinerary has one
            if (itinerary.coverImageUrl != null)
              _CardCoverImage(
                url: itinerary.coverImageUrl!.startsWith('/')
                    ? '$kApiBaseUrl${itinerary.coverImageUrl}'
                    : itinerary.coverImageUrl!,
              ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white.withValues(alpha: 0.95),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + visibility badge + optional share icon
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          itinerary.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      _VisibilityBadge(itinerary: itinerary),
                      if (itinerary.visibility !=
                          ItineraryVisibility.onlyMe) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => ref
                              .read(shareServiceProvider)
                              .shareItinerary(itinerary),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.share_outlined,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
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
                            '${itinerary.stopsCount} stop${itinerary.stopsCount == 1 ? '' : 's'}',
                      ),
                      if (itinerary.ratingAvg != null)
                        _Stat(
                          icon: Icons.star_rounded,
                          label:
                              '${itinerary.ratingAvg!.toStringAsFixed(1)} (${itinerary.ratingCount})',
                          iconColor: ratingColor(itinerary.ratingAvg!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardCoverImage extends StatefulWidget {
  final String url;
  const _CardCoverImage({required this.url});

  @override
  State<_CardCoverImage> createState() => _CardCoverImageState();
}

class _CardCoverImageState extends State<_CardCoverImage> {
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    if (_error) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: AspectRatio(
        aspectRatio: 1200 / 630,
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _error = true);
            });
            return const SizedBox.shrink();
          },
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
