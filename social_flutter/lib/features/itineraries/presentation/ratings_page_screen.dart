// features/itineraries/presentation/ratings_page_screen.dart
//
// Screen: /itineraries/:id/ratings
// Shows the full community ratings page: aggregate, distribution bars,
// and individual rater list.
//
// Pull-to-refresh works in every state (loading, error, empty, data) because
// AlwaysScrollableScrollPhysics is set on the CustomScrollView and all states
// are expressed as slivers — so the pull gesture is always recognized.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

class RatingsPageScreen extends ConsumerWidget {
  final String itineraryId;

  const RatingsPageScreen({super.key, required this.itineraryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsPageProvider(itineraryId));
    final page = ratingsAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ratings'),
        bottom: (page != null && page.ratingCount > 0)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${page.ratingAvg!.toStringAsFixed(1)} ★  ·  ${page.ratingCount} ratings',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(ratingsPageProvider(itineraryId).notifier).refresh(),
        child: CustomScrollView(
          // AlwaysScrollableScrollPhysics ensures the pull gesture is detected
          // even when the content does not overflow the viewport (e.g. empty
          // state or error state with no list items below).
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
            else if (page != null && page.ratingCount == 0)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No ratings yet',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Be the first to rate this itinerary',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else if (page != null) ...[
              // ----------------------------------------------------------------
              // Sliver 1 — Summary header
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    children: [
                      Text(
                        page.ratingAvg!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _StarRow(avg: page.ratingAvg!),
                      const SizedBox(height: 4),
                      Text(
                        'Based on ${page.ratingCount} rating${page.ratingCount == 1 ? '' : 's'}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),

              // ----------------------------------------------------------------
              // Sliver 2 — Distribution bars (always 5 rows, even if count = 0)
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(
                    children: [5, 4, 3, 2, 1].map((stars) {
                      final pct = page.distribution.percentageFor(stars);
                      final count = switch (stars) {
                        5 => page.distribution.five,
                        4 => page.distribution.four,
                        3 => page.distribution.three,
                        2 => page.distribution.two,
                        _ => page.distribution.one,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '$stars★',
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade200,
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '$count',
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${(pct * 100).round()}%',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // ----------------------------------------------------------------
              // Sliver 3 — Section header
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                  child: Text(
                    'All Ratings',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),

              // ----------------------------------------------------------------
              // Sliver 4 — Individual rating tiles
              // ----------------------------------------------------------------
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _RatingListTile(rating: page.ratings[index]),
                  childCount: page.ratings.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Five partially-filled stars proportional to the average.
class _StarRow extends StatelessWidget {
  final double avg;

  const _StarRow({required this.avg});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1;
        final IconData icon;
        if (avg >= starValue) {
          icon = Icons.star_rounded;
        } else if (avg >= starValue - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, color: Colors.amber, size: 24);
      }),
    );
  }
}

/// One tile in the ratings list — shows rater identity + score + time.
class _RatingListTile extends StatelessWidget {
  final RatingWithUser rating;

  const _RatingListTile({required this.rating});

  @override
  Widget build(BuildContext context) {
    final user = rating.user;

    final Widget tile = ListTile(
      leading: user.isDeleted
          ? Opacity(
              opacity: 0.5,
              child: CircleAvatar(
                backgroundColor: Colors.grey.shade300,
                child:
                    const Icon(Icons.person_off, color: Colors.grey, size: 20),
              ),
            )
          : UserAvatar(avatarUrl: user.avatarUrl, radius: 20),
      title: user.isDeleted
          ? Text(
              'Deleted User',
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: Colors.grey.shade500),
            )
          : Text(
              user.displayNameOrFallback,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
      subtitle: Text(rating.timeAgo),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final filled = i < rating.score;
          return Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: filled ? Colors.amber : Colors.grey.shade400,
          );
        }),
      ),
      // Deleted users have no profile to navigate to — onTap must be null.
      onTap: user.isDeleted
          ? null
          : () => context.push('/profile/${user.userId}'),
    );

    if (user.isDeleted) {
      return Opacity(opacity: 0.6, child: tile);
    }
    return tile;
  }
}
