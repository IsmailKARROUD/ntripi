// features/itineraries/presentation/ratings_page_screen.dart
//
// RatingsHubScreen — /itineraries/:id/ratings
//
// Layout:
//   Sliver 1 — Dimension averages list (Overall + 4 sub-dimensions)
//   Sliver 2 — "All Raters" section header
//   Sliver 3 — SliverList of individual rater tiles (overall score shown)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
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
    final page = ratingsAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Ratings')),
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
            else if (page != null) ...[
              // ----------------------------------------------------------------
              // Sliver 1 — Dimension averages
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: _DimensionList(
                  itineraryId: itineraryId,
                  page: page,
                ),
              ),

              // ----------------------------------------------------------------
              // Sliver 2 — Section header
              // ----------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'All Raters',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),

              // ----------------------------------------------------------------
              // Sliver 3 — Rater tiles (overall score)
              // ----------------------------------------------------------------
              if (page.ratingCount == 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.star_border,
                              size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('No ratings yet',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Be the first to rate this itinerary',
                              style:
                                  TextStyle(color: Colors.grey.shade600)),
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

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    ),),);
  }
}

// ---------------------------------------------------------------------------
// Dimension averages list
// ---------------------------------------------------------------------------

class _DimensionList extends StatelessWidget {
  final String itineraryId;
  final RatingsPage page;

  const _DimensionList({required this.itineraryId, required this.page});

  /// Compute average + count for a given dimension from the ratings list.
  (double?, int) _stats(DimensionKey dim) {
    if (dim == DimensionKey.overall) {
      return (page.ratingAvg, page.ratingCount);
    }
    final scores = page.ratings
        .map((r) => r.scoreForDimension(dim))
        .whereType<int>()
        .toList();
    if (scores.isEmpty) return (null, 0);
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    return (avg, scores.length);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: DimensionKey.values.map((dim) {
        final (avg, count) = _stats(dim);
        final hasData = count > 0;

        return Opacity(
          opacity: hasData ? 1.0 : 0.5,
          child: ListTile(
            leading: Icon(
              dim.icon,
              color: kBark,
            ),
            title: Text(dim.label),
            subtitle: dim != DimensionKey.overall
                ? Text(
                    dim.description,
                    style: const TextStyle(fontSize: 12),
                  )
                : null,
            trailing: hasData
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        avg!.toStringAsFixed(1),
                        style:  TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: ratingColor(avg),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($count)',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade400),
                    ],
                  )
                : Text(
                    'No ratings yet',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                  ),
            onTap: hasData
                ? () => context.push(
                      '/itineraries/$itineraryId/ratings/${dim.pathSegment}',
                    )
                : null,
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets (also used by DimensionRatingsScreen via import)
// ---------------------------------------------------------------------------

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
                  backgroundColor: Colors.grey.shade200,
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
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
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

/// One rater tile — shows avatar, name, time, a 5-star trailing widget,
/// and an expandable Markdown review note when the rater left one.
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
          ? Opacity(
              opacity: 0.5,
              child: CircleAvatar(
                backgroundColor: Colors.grey.shade300,
                child: const Icon(Icons.person_off,
                    color: Colors.grey, size: 20),
              ),
            )
          : UserAvatar(avatarUrl: user.avatarUrl, radius: 20),
      title: user.isDeleted
          ? Text(
              'Deleted User',
              style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade500),
            )
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
            color: filled ? ratingColor(score.toDouble()) : Colors.grey.shade400,
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
                padding: const EdgeInsets.only(left: 72, right: 16, bottom: 4),
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
                Icon(Icons.format_quote,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  expanded ? 'Hide review' : 'Read review',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.grey.shade600,
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
