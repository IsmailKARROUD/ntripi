// features/itineraries/presentation/dimension_ratings_screen.dart
//
// DimensionRatingsScreen — /itineraries/:id/ratings/:dimension
//
// Shows hero average, distribution bars, and the filtered rater list
// for one rating dimension (overall | safety | experience |
// accessibility | family_friendly).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

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
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final ratingsAsync = ref.watch(ratingsPageProvider(itineraryId));
    final page = ratingsAsync.value;
    // Without this the tile offers Report/Block on the viewer's OWN review —
    // the guard inside compares against it.
    final viewerId = ref.watch(myProfileProvider).value?.id;

    final filtered = page != null ? _filtered(page.ratings) : <RatingWithUser>[];
    final avg = _avg(filtered);
    final dist = _distribution(filtered);

    return Scaffold(
      backgroundColor: nt.surface,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: EditorialTopBar(
                title: l10n.dimensionRatingTitle(dimension.label(l10n))),
          ),
          Container(height: 1, color: nt.border),
          Expanded(
            child: Center(
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
                child: Center(child: NTripiRouteLoader()),
              )
            else if (ratingsAsync.hasError && page == null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: nt.danger),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context)!.couldNotLoadRatings),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref
                            .read(ratingsPageProvider(itineraryId).notifier)
                            .refresh(),
                        child: Text(AppLocalizations.of(context)!.retry),
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
                      Icon(dimension.icon, size: 56, color: nt.text3),
                      const SizedBox(height: 12),
                      Text(
                        l10n.noRatingsYetFor(
                            dimension.label(l10n).toLowerCase()),
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
                              color: nt.bark),
                          const SizedBox(width: 10),
                          Text(
                            avg!.toStringAsFixed(1),
                            style:  TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              color: nt.rating(avg),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      RatingStarRow(avg: avg, dimension: dimension),
                      const SizedBox(height: 6),
                      Text(
                        l10n.basedOnRatings(filtered.length),
                        style: TextStyle(color: nt.text2),
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
                    l10n.ratersLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: nt.text2,
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
                    viewerId: viewerId,
                  ),
                  childCount: filtered.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
          ),
        ),
          ),
        ],
      ),
    );
  }
}
