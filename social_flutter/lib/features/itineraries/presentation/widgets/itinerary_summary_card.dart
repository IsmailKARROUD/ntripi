// widgets/itinerary_summary_card.dart — Editorial-style card used on list and
// profile screens.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/shared/widgets/visibility_badge.dart';

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
    final coverUrl = itinerary.coverImageUrl != null
        ? (itinerary.coverImageUrl!.startsWith('/')
            ? '$kApiBaseUrl${itinerary.coverImageUrl}'
            : itinerary.coverImageUrl!)
        : null;

    return GestureDetector(
      onTap: () => context.push('/itineraries/${itinerary.id}'),
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image — 120px tall
            SizedBox(
              height: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverSlot(url: coverUrl),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: VisibilityBadge(visibility: itinerary.visibility, onDark: true),
                  ),
                ],
              ),
            ),
            // Content area
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          itinerary.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kBark,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (itinerary.ratingAvg != null) ...[
                        const SizedBox(width: 8),
                        _StarRating(
                          score: itinerary.ratingAvg!,
                          count: itinerary.ratingCount,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        label: itinerary.formattedDuration,
                      ),
                      _MetaChip(
                        icon: Icons.payments_rounded,
                        label: itinerary.formattedCost,
                      ),
                      _MetaChip(
                        icon: Icons.location_on_rounded,
                        label:
                            '${itinerary.stopsCount} stop${itinerary.stopsCount == 1 ? '' : 's'}',
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

// Cover image: shows CachedNetworkImage when URL is available, else a gradient
// placeholder using the brand palette.
class _CoverSlot extends StatefulWidget {
  final String? url;
  const _CoverSlot({this.url});

  @override
  State<_CoverSlot> createState() => _CoverSlotState();
}

class _CoverSlotState extends State<_CoverSlot> {
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    if (widget.url != null && !_error) {
      return CachedNetworkImage(
        imageUrl: widget.url!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _error = true);
          });
          return const _CoverPlaceholder();
        },
      );
    }
    return const _CoverPlaceholder();
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kMist, Color(0xFFB8D9C4)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.map_rounded, size: 36, color: kCanopy),
      ),
    );
  }
}

// Small meta chip — icon + label on a subtle background.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x0A000000), // rgba(0,0,0,0.04)
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kBark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: kBark,
            ),
          ),
        ],
      ),
    );
  }
}

// Inline star rating — score + (count) in the rating semantic color.
class _StarRating extends StatelessWidget {
  final double score;
  final int count;

  const _StarRating({required this.score, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = ratingColor(score);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          score.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          ' ($count)',
          style: const TextStyle(
            fontSize: 11,
            color: kText3,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

