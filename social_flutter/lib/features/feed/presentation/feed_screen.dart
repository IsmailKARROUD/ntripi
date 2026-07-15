// features/feed/presentation/feed_screen.dart — Public discovery feed.
//
// Lists public itineraries across all users with a Top / Recent toggle and
// infinite scroll. Reuses the shared loaders, error helper, and itinerary card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart' show extractErrorMessage;
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/feed/presentation/widgets/feed_card.dart';
import 'package:social_flutter/features/feed/providers/feed_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Prefetch the next page before the user hits the very bottom.
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final sort = ref.watch(feedSortProvider);
    final feedAsync = ref.watch(feedProvider);
    // hasMore is plain notifier state; it's re-read on every rebuild, and the
    // list rebuilds whenever a page is appended, so the trailing loader tracks it.
    final hasMore = ref.read(feedProvider.notifier).hasMore;

    return Scaffold(
      backgroundColor: nt.surface,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
            ),
            child: RefreshIndicator(
              onRefresh: () => ref.read(feedProvider.notifier).refresh(),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context, l10n, sort)),
                  ...feedAsync.when(
                    loading: () => const [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: NTripiItineraryLoader()),
                      ),
                    ],
                    error: (error, _) => [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _errorState(context, l10n, error),
                      ),
                    ],
                    data: (items) {
                      if (items.isEmpty) {
                        return [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _emptyState(
                              sort == FeedSort.top
                                  ? l10n.feedTopEmpty
                                  : l10n.feedEmpty,
                            ),
                          ),
                        ];
                      }
                      return [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= items.length) {
                                  // Trailing load-more spinner.
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                        child: NTripiRingLoader(size: 36)),
                                  );
                                }
                                return FeedCard(
                                  key: ValueKey(items[index].itinerary.id),
                                  item: items[index],
                                );
                              },
                              childCount: items.length + (hasMore ? 1 : 0),
                            ),
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, AppLocalizations l10n, FeedSort sort) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.feedTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: nt.bark,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<FeedSort>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: FeedSort.top,
                label: Text(l10n.feedTabTop),
                icon: const Icon(Icons.local_fire_department_outlined, size: 16),
              ),
              ButtonSegment(
                value: FeedSort.recent,
                label: Text(l10n.feedTabRecent),
                icon: const Icon(Icons.schedule_outlined, size: 16),
              ),
            ],
            selected: {sort},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(feedSortProvider.notifier).set(s.first),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    final nt = context.nt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 64, color: nt.text3),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: nt.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(
      BuildContext context, AppLocalizations l10n, Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            extractErrorMessage(error, l10n),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.read(feedProvider.notifier).refresh(),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}
