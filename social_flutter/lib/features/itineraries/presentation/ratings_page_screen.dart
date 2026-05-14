// features/itineraries/presentation/ratings_page_screen.dart
//
// RatingsHubScreen — /itineraries/:id/ratings
//
// Layout (Screen 12 design):
//   1. Overall hero card  — large score + stars + count
//   2. By dimension       — progress-bar rows per sub-dimension
//   3. Your rating        — viewer's stars + Change button
//   4. All raters         — existing list of individual rater tiles

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

// Keep the old name exported so the router import doesn't break.
typedef RatingsPageScreen = RatingsHubScreen;

class RatingsHubScreen extends ConsumerWidget {
  final String itineraryId;

  const RatingsHubScreen({super.key, required this.itineraryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsPageProvider(itineraryId));
    final myRating = ref.watch(myRatingProvider(itineraryId)).valueOrNull;
    final page = ratingsAsync.valueOrNull;

    return Scaffold(
      backgroundColor: kSand,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(backgroundColor: kSand, title: const Text('Ratings')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
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
                              size: 48, color: Color(0xFFBA1A1A)),
                          const SizedBox(height: 12),
                          const Text('Could not load ratings'),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => ref
                                .read(
                                    ratingsPageProvider(itineraryId).notifier)
                                .refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (page != null) ...[
                  // ── 1. Overall hero ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _OverallHero(page: page),
                  ),

                  // ── 2. By dimension ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _DimensionSection(
                        itineraryId: itineraryId, page: page),
                  ),

                  // ── 3. Your rating ───────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _YourRatingSection(
                      itineraryId: itineraryId,
                      myRating: myRating,
                      ref: ref,
                    ),
                  ),

                  // ── 4. All raters header ─────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        'ALL RATERS',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kText2,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),

                  // ── 4. Rater tiles ───────────────────────────────────────
                  if (page.ratingCount == 0)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.star_border, size: 56, color: kText3),
                              SizedBox(height: 12),
                              Text('No ratings yet',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: kBark)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) =>
                            _RatingListTile(rating: page.ratings[i]),
                        childCount: page.ratings.length,
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 1. Overall hero card ─────────────────────────────────────────────────────
class _OverallHero extends StatelessWidget {
  final RatingsPage page;
  const _OverallHero({required this.page});

  @override
  Widget build(BuildContext context) {
    final score = page.ratingAvg;
    final count = page.ratingCount;

    if (count == 0) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorder),
        ),
        child: const Center(
          child: Column(
            children: [
              Text('OVERALL',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.6)),
              SizedBox(height: 12),
              Icon(Icons.star_border_rounded, size: 44, color: kText3),
              SizedBox(height: 8),
              Text('No ratings yet',
                  style: TextStyle(fontSize: 13, color: kText2)),
            ],
          ),
        ),
      );
    }

    final color = ratingColor(score!);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          const Text(
            'OVERALL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kText2,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return Icon(
                star <= score.round()
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 18,
                color: star <= score.round() ? color : const Color(0xFFE4E4E4),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            '$count traveler${count == 1 ? '' : 's'} rated this',
            style: const TextStyle(fontSize: 12, color: kText2),
          ),
        ],
      ),
    );
  }
}

// ─── 2. By dimension section ──────────────────────────────────────────────────
class _DimensionSection extends StatelessWidget {
  final String itineraryId;
  final RatingsPage page;

  const _DimensionSection(
      {required this.itineraryId, required this.page});

  (double?, int) _stats(DimensionKey dim) {
    final scores = page.ratings
        .map((r) => r.scoreForDimension(dim))
        .whereType<int>()
        .toList();
    if (scores.isEmpty) return (null, 0);
    return (scores.reduce((a, b) => a + b) / scores.length, scores.length);
  }

  @override
  Widget build(BuildContext context) {
    final dims = DimensionKey.values
        .where((d) => d != DimensionKey.overall)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            'BY DIMENSION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kText2,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < dims.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 14, endIndent: 14),
                _DimRow(
                  dim: dims[i],
                  stats: _stats(dims[i]),
                  onTap: _stats(dims[i]).$2 >= 1
                      ? () => context.push(
                            '/itineraries/$itineraryId/ratings/${dims[i].pathSegment}',
                          )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DimRow extends StatelessWidget {
  final DimensionKey dim;
  final (double?, int) stats;
  final VoidCallback? onTap;

  const _DimRow(
      {required this.dim, required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (avg, count) = stats;
    final insufficient = count < 3;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: kMist,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(dim.icon, size: 15, color: kForest),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dim.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kBark,
                    ),
                  ),
                ),
                if (avg == null || insufficient)
                  const Text(
                    'Not enough ratings',
                    style: TextStyle(
                      fontSize: 11,
                      color: kText3,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    avg.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ratingColor(avg),
                    ),
                  ),
              ],
            ),
            // Progress bar
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: (avg != null && !insufficient) ? avg / 5 : 0,
                    backgroundColor: const Color(0xFFEFECE5),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      (avg != null && !insufficient)
                          ? ratingColor(avg)
                          : kText3,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 3),
              child: Text(
                '$count ${count == 1 ? 'rating' : 'ratings'}',
                style: const TextStyle(fontSize: 10, color: kText3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 3. Your rating section ───────────────────────────────────────────────────
class _YourRatingSection extends StatelessWidget {
  final String itineraryId;
  final dynamic myRating; // MyRating?
  final WidgetRef ref;

  const _YourRatingSection({
    required this.itineraryId,
    required this.myRating,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: const [
              Icon(Icons.person_rounded, size: 13, color: kForest),
              SizedBox(width: 6),
              Text(
                'YOUR RATING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kForest,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            // kMist tint makes the viewer's own rating visually distinct
            // from the community stats above (which use plain kSurface).
            color: kMist.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kForest.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: myRating != null
                ? Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (i) => Icon(
                              i < myRating.stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 22,
                              color: i < myRating.stars
                                  ? ratingColor(myRating.stars.toDouble())
                                  : const Color(0xFFE4E4E4),
                            )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13, color: kText2),
                            children: [
                              const TextSpan(text: 'You rated this '),
                              TextSpan(
                                text: '${myRating.stars}/5',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: kBark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => showRateItineraryDialog(
                          context,
                          ref,
                          itineraryId: itineraryId,
                          current: myRating,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kBorder, width: 1.5),
                          ),
                          child: const Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: kBark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => showRateItineraryDialog(
                        context,
                        ref,
                        itineraryId: itineraryId,
                        current: null,
                      ),
                      icon: const Icon(Icons.star_rounded, size: 16),
                      label: const Text('Rate this trip'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

/// Five partially-filled stars proportional to the average.
class RatingStarRow extends StatelessWidget {
  final double avg;
  final double size;

  const RatingStarRow({super.key, required this.avg, this.size = 24});

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
        return Icon(icon, color: ratingColor(avg), size: size);
      }),
    );
  }
}

/// Distribution bars widget — reused by both hub and dimension screens.
class RatingDistributionBars extends StatelessWidget {
  final Map<int, int> dist;

  const RatingDistributionBars({super.key, required this.dist});

  @override
  Widget build(BuildContext context) {
    final total = dist.values.fold(0, (a, b) => a + b);
    return Column(
      children: [5, 4, 3, 2, 1].map((stars) {
        final count = dist[stars] ?? 0;
        final pct = total == 0 ? 0.0 : count / total;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text('$stars★',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: kBorder,
                  color: ratingColor(stars.toDouble()),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: Text('$count',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 36,
                child: Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(fontSize: 11, color: kText2),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// One rater tile.
class _RatingListTile extends StatefulWidget {
  final RatingWithUser rating;
  final DimensionKey dimension;

  const _RatingListTile({
    required this.rating,
    this.dimension = DimensionKey.overall,
  });

  @override
  State<_RatingListTile> createState() => _RatingListTileState();
}

class _RatingListTileState extends State<_RatingListTile> {
  bool _noteExpanded = false;

  @override
  Widget build(BuildContext context) {
    final rating = widget.rating;
    final user = rating.user;
    final score = rating.scoreForDimension(widget.dimension) ?? rating.score;
    final hasNote = rating.note != null && rating.note!.trim().isNotEmpty;

    final Widget tile = ListTile(
      leading: user.isDeleted
          ? const Opacity(
              opacity: 0.5,
              child: CircleAvatar(
                backgroundColor: kMist,
                child: Icon(Icons.person_off, color: kText3, size: 20),
              ),
            )
          : UserAvatar(avatarUrl: user.avatarUrl, radius: 20),
      title: user.isDeleted
          ? const Text('Deleted User',
              style: TextStyle(fontStyle: FontStyle.italic, color: kText3))
          : Text(user.displayNameOrFallback,
              style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(rating.timeAgo),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final filled = i < score;
          return Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: filled ? ratingColor(score.toDouble()) : kText3,
          );
        }),
      ),
      onTap: user.isDeleted
          ? null
          : () => context.push('/profile/${user.userId}'),
    );

    final Widget body = hasNote
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tile,
              Padding(
                padding:
                    const EdgeInsets.only(left: 72, right: 16, bottom: 4),
                child: _ReviewNote(
                  note: rating.note!,
                  expanded: _noteExpanded,
                  onToggle: () =>
                      setState(() => _noteExpanded = !_noteExpanded),
                ),
              ),
            ],
          )
        : tile;

    return user.isDeleted ? Opacity(opacity: 0.6, child: body) : body;
  }
}

class _ReviewNote extends StatelessWidget {
  final String note;
  final bool expanded;
  final VoidCallback onToggle;

  const _ReviewNote({
    required this.note,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.format_quote, size: 14, color: kText2),
                const SizedBox(width: 4),
                Text(
                  expanded ? 'Hide review' : 'Read review',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kText2,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: kText2,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InertMarkdownBody(data: note),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// Export _RatingListTile for DimensionRatingsScreen via the public alias.
// ignore: library_private_types_in_public_api
typedef RatingListTile = _RatingListTile;
