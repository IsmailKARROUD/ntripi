// features/feed/providers/feed_providers.dart — Riverpod state for the public
// discovery feed.
//
// Providers:
//   feedSortProvider — current sort mode (Top / Recent). Watched by FeedNotifier
//                      so flipping the toggle re-fetches page 0 automatically.
//   feedProvider     — paginated list of FeedItem with infinite scroll.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/features/feed/data/feed_repository.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';

/// Feed sort mode. The [value] is the literal sent to the backend `sort` param.
enum FeedSort {
  recent('recent'),
  top('top');

  final String value;
  const FeedSort(this.value);
}

final feedSortProvider = StateProvider<FeedSort>((ref) => FeedSort.recent);

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// Whether another page may exist — drives the trailing load-more indicator.
  bool get hasMore => _hasMore;

  @override
  Future<List<FeedItem>> build() async {
    // Watching the sort provider means changing it re-runs build() on this same
    // notifier instance, re-fetching page 0 and resetting the offset for free.
    final sort = ref.watch(feedSortProvider);
    final first = await ref
        .read(feedRepositoryProvider)
        .getFeed(sort: sort.value, offset: 0);
    _offset = first.length;
    _hasMore = first.length == kFeedPageSize;
    return first;
  }

  /// Append the next page. No-op while a load is in flight or the end is reached.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.value;
    if (current == null) return;
    _loadingMore = true;
    try {
      final sort = ref.read(feedSortProvider);
      final next = await ref
          .read(feedRepositoryProvider)
          .getFeed(sort: sort.value, offset: _offset);
      _offset += next.length;
      _hasMore = next.length == kFeedPageSize;
      state = AsyncData([...current, ...next]);
    } finally {
      _loadingMore = false;
    }
  }

  /// Pull-to-refresh / retry — re-fetch page 0, bypassing the HTTP cache.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final sort = ref.read(feedSortProvider);
      final first = await ref.read(feedRepositoryProvider).getFeed(
            sort: sort.value,
            offset: 0,
            forceRefresh: true,
          );
      _offset = first.length;
      _hasMore = first.length == kFeedPageSize;
      return first;
    });
  }
}

final feedProvider =
    AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(() => FeedNotifier());
