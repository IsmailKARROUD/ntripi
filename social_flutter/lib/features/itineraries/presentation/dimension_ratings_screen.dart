// features/itineraries/presentation/dimension_ratings_screen.dart
//
// DimensionRatingsScreen — /itineraries/:id/ratings/:dimension
//
// Shows hero average, distribution bars, and the filtered rater list
// for one rating dimension (overall | safety | experience |
// accessibility | family_friendly).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class DimensionRatingsScreen extends ConsumerWidget {
  final String itineraryId;
  final DimensionKey dimension;

  const DimensionRatingsScreen({
    super.key,
    required this.itineraryId,
    required this.dimension,
  });

  List<RatingWithUser> _filtered(List<RatingWithUser> all) =>
      all.where((r) => r.scoreForDimension(dimension) != null).toList();

  Map<int, int> _distribution(List<RatingWithUser> filtered) {
    final dist = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final r in filtered) {
      final s = r.scoreForDimension(dimension);
      if (s != null) dist[s] = dist[s]! + 1;
    }
    return dist;
  }

  double? _avg(List<RatingWithUser> filtered) {
    if (filtered.isEmpty) return null;
    final scores = filtered
        .map((r) => r.scoreForDimension(dimension)!)
        .toList();
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsPageProvider(itineraryId));
    final page = ratingsAsync.valueOrNull;

    final filtered = page != null ? _filtered(page.ratings) : <RatingWithUser>[];
    final avg = _avg(filtered);
    final dist = _distribution(filtered);

    return Scaffold(
      appBar: AppBar(title: Text('${dimension.label} Rating')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(ratingsPageProvider(itineraryId).notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (ratingsAsync.isLoading && page == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (ratingsAsync.hasError && page == null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      const Text('Could not load ratings'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref
                            .read(ratingsPageProvider(itineraryId).notifier)
                            .refresh(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(dimension.icon, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No ratings yet for ${dimension.label.toLowerCase()}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // ----------------------------------------------------------------
              // Sliver 1 — Hero average
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Icon(dimension.icon,
                              size: 36,
                              color: dimension == DimensionKey.overall
                                  ? Colors.amber
                                  : Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Text(
                            avg!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      RatingStarRow(avg: avg),
                      const SizedBox(height: 6),
                      Text(
                        'Based on ${filtered.length} '
                        'rating${filtered.length == 1 ? '' : 's'}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),

              // ----------------------------------------------------------------
              // Sliver 2 — Distribution bars
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 8),
                  child: RatingDistributionBars(dist: dist),
                ),
              ),

              // ----------------------------------------------------------------
              // Sliver 3 — Section header
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Raters',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),

              // ----------------------------------------------------------------
              // Sliver 4 — Filtered rater tiles
              // ----------------------------------------------------------------
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => RatingListTile(
                    rating: filtered[i],
                    dimension: dimension,
                  ),
                  childCount: filtered.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    ),),);
  }
}
