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
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/features/reports/presentation/ugc_actions.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

// Keep the old name exported so the router import doesn't break.
typedef RatingsPageScreen = RatingsHubScreen;

class RatingsHubScreen extends ConsumerWidget {
  final String itineraryId;

  const RatingsHubScreen({super.key, required this.itineraryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final ratingsAsync = ref.watch(ratingsPageProvider(itineraryId));
    // Your own review gets no report action — you don't report yourself.
    final viewerId = ref.watch(myProfileProvider).value?.id;
    final myRating = ref.watch(myRatingProvider(itineraryId)).value;
    final page = ratingsAsync.value;

    return Scaffold(
      backgroundColor: nt.sand,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(backgroundColor: nt.sand, title: Text(AppLocalizations.of(context)!.ratingsTitle)),
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
                                .read(
                                    ratingsPageProvider(itineraryId).notifier)
                                .refresh(),
                            child: Text(AppLocalizations.of(context)!.retry),
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
                        AppLocalizations.of(context)!
                            .allRatersLabel
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: nt.text2,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),

                  // ── 4. Rater tiles ───────────────────────────────────────
                  if (page.ratingCount == 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.star_border, size: 56, color: nt.text3),
                              const SizedBox(height: 12),
                              Text(AppLocalizations.of(context)!.noRatingsYet,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: nt.bark)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) =>
                            _RatingListTile(
                              rating: page.ratings[i],
                              viewerId: viewerId,
                            ),
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
    final nt = context.nt;
    final score = page.ratingAvg;
    final count = page.ratingCount;

    if (count == 0) {
    final nt = context.nt;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: nt.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: nt.border),
        ),
        child: Center(
          child: Column(
            children: [
              Text(AppLocalizations.of(context)!.ratingsOverallLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: nt.text2,
                      letterSpacing: 0.6)),
              const SizedBox(height: 12),
              Icon(Icons.star_border_rounded, size: 44, color: nt.text3),
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context)!.noRatingsYet,
                  style: TextStyle(fontSize: 13, color: nt.text2)),
            ],
          ),
        ),
      );
    }

    final color = nt.rating(score!);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: nt.border),
      ),
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context)!.ratingsOverallLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: nt.text2,
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
                color: star <= score.round() ? color : nt.border,
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)!.travelersRatedThis(count),
            style: TextStyle(fontSize: 12, color: nt.text2),
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
    final nt = context.nt;
    final dims = DimensionKey.values
        .where((d) => d != DimensionKey.overall)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            AppLocalizations.of(context)!.byDimensionLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: nt.text2,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: nt.border),
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
    final nt = context.nt;
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
                    color: nt.mist,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(dim.icon, size: 15, color: nt.forest),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dim.label(AppLocalizations.of(context)!),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: nt.bark,
                    ),
                  ),
                ),
                if (avg == null || insufficient)
                  Text(
                    AppLocalizations.of(context)!.notEnoughRatings,
                    style: TextStyle(
                      fontSize: 11,
                      color: nt.text3,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    avg.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: nt.rating(avg),
                    ),
                  ),
              ],
            ),
            // Progress bar
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 36, top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: (avg != null && !insufficient) ? avg / 5 : 0,
                    backgroundColor: nt.sand,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      (avg != null && !insufficient)
                          ? nt.rating(avg)
                          : nt.text3,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 36, top: 3),
              child: Text(
                AppLocalizations.of(context)!.ratingCount(count),
                style: TextStyle(fontSize: 10, color: nt.text3),
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
    final nt = context.nt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Icon(Icons.person_rounded, size: 13, color: nt.forest),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.yourRating.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: nt.forest,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            // nt.mist tint makes the viewer's own rating visually distinct
            // from the community stats above (which use plain nt.surface).
            color: nt.mist.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: nt.forest.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
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
                                  ? nt.rating(myRating.stars.toDouble())
                                  : nt.border,
                            )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                                fontSize: 13, color: nt.text2),
                            children: [
                              TextSpan(
                                  text:
                                      '${AppLocalizations.of(context)!.youRatedThis} '),
                              TextSpan(
                                text: '${myRating.stars}/5',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: nt.bark,
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
                            border: Border.all(color: nt.border, width: 1.5),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.changeButton,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: nt.bark,
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
                      label: Text(AppLocalizations.of(context)!.rateThisTrip),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

/// Five partially-filled glyphs proportional to the average.
/// Glyph set follows the dimension (people for crowdedness, stars otherwise).
class RatingStarRow extends StatelessWidget {
  final double avg;
  final double size;
  final DimensionKey dimension;

  const RatingStarRow({
    super.key,
    required this.avg,
    this.size = 24,
    this.dimension = DimensionKey.overall,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final glyphs = dimension.ratingGlyphs;
    final inverted = dimension.invertedRating;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1;
        final IconData icon;
        if (inverted) {
          // Uncrowded: fill grows from the right (fewer filled = quieter).
          if (avg <= starValue - 1) {
            icon = glyphs.filled;
          } else if (avg <= starValue - 0.5) {
            icon = glyphs.half;
          } else {
            icon = glyphs.empty;
          }
        } else if (avg >= starValue) {
          icon = glyphs.filled;
        } else if (avg >= starValue - 0.5) {
          icon = glyphs.half;
        } else {
          icon = glyphs.empty;
        }
        return Icon(icon, color: nt.rating(avg), size: size);
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
    final nt = context.nt;
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
                    textAlign: TextAlign.end),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: nt.border,
                  color: nt.rating(stars.toDouble()),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: Text('$count',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.end),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 36,
                child: Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(fontSize: 11, color: nt.text2),
                  textAlign: TextAlign.end,
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
class _RatingListTile extends ConsumerWidget {
  final RatingWithUser rating;
  final DimensionKey dimension;

  /// Null when the viewer wrote this review — you don't report yourself.
  final String? viewerId;

  const _RatingListTile({
    required this.rating,
    this.dimension = DimensionKey.overall,
    this.viewerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final user = rating.user;
    final score = rating.scoreForDimension(dimension) ?? rating.score;
    final hasNote = rating.note != null && rating.note!.trim().isNotEmpty;

    final Widget tile = ListTile(
      leading: user.isDeleted
          ? Opacity(
              opacity: 0.5,
              child: CircleAvatar(
                backgroundColor: nt.mist,
                child: Icon(Icons.person_off, color: nt.text3, size: 20),
              ),
            )
          : UserAvatar(avatarUrl: user.avatarUrl, radius: 20),
      title: user.isDeleted
          ? Text(l10n.deletedUser,
              style: TextStyle(fontStyle: FontStyle.italic, color: nt.text3))
          : Text(user.displayNameOrFallback(l10n),
              style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(rating.timeAgo(l10n)),
      // A review is user content like any other, so it needs its own report
      // action — the id is absent only for responses cached before it existed.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(5, (i) {
            final glyphs = dimension.ratingGlyphs;
            final inverted = dimension.invertedRating;
            // Uncrowded: fill from the right; tint empties too.
            final filled = inverted ? (i + 1) > score : i < score;
            return Icon(
              filled ? glyphs.filled : glyphs.empty,
              size: 16,
              color: inverted
                  ? nt.rating(score.toDouble())
                  : (filled ? nt.rating(score.toDouble()) : nt.text3),
            );
          }),
          if (rating.id != null &&
              !user.isDeleted &&
              user.userId != viewerId)
            UgcActionsMenu(
              target: ReportTarget.rating(rating.id!),
              authorUserId: user.userId,
              authorUsername: user.username,
            ),
        ],
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
                    const EdgeInsetsDirectional.only(start: 72, end: 16, bottom: 4),
                child: _ReviewNote(note: rating.note!),
              ),
            ],
          )
        : tile;

    return user.isDeleted ? Opacity(opacity: 0.6, child: body) : body;
  }
}

/// One-line preview of a rater's note that expands to full markdown on tap —
/// mirrors the expandable-notes pattern in stop_card.dart (`_ReadNotesSection`).
class _ReviewNote extends StatefulWidget {
  final String note;

  const _ReviewNote({required this.note});

  @override
  State<_ReviewNote> createState() => _ReviewNoteState();
}

class _ReviewNoteState extends State<_ReviewNote> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(fontSize: 13, height: 1.4, color: nt.text2);
    final linkStyle = TextStyle(
      fontSize: 12,
      color: nt.forest,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.note, style: style),
          maxLines: 1,
          // must match the rendered Text's direction or the overflow check lies for Arabic notes
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expanded)
              InertMarkdownBody(data: widget.note)
            else
              GestureDetector(
                // tapping the one-line preview reveals the rest — no-op when it already fits
                onTap:
                    overflows ? () => setState(() => _expanded = true) : null,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  widget.note,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (overflows || _expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? l10n.viewLess : l10n.viewMore,
                    style: linkStyle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Export _RatingListTile for DimensionRatingsScreen via the public alias.
// ignore: library_private_types_in_public_api
typedef RatingListTile = _RatingListTile;
