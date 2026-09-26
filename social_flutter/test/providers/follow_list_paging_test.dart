// test/providers/follow_list_paging_test.dart — the followers / following
// lists page through the whole set instead of stopping at the server's first
// page (which is what made a 150-follower account show 20).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/shared/models/follow.dart';

/// Serves [total] users in pages of [kFollowListPageSize] and records every
/// offset it was asked for.
class _PagedFollowRepo implements FollowRepository {
  _PagedFollowRepo(this.total);
  final int total;
  final List<int> offsets = [];

  List<FollowerListItem> _page(int offset, int limit) {
    offsets.add(offset);
    final end = (offset + limit).clamp(0, total);
    return [
      for (var i = offset; i < end; i++)
        FollowerListItem(id: 'u$i', username: 'user$i', isPrivate: false),
    ];
  }

  @override
  Future<List<FollowerListItem>> getFollowers(
    String userId, {
    int limit = kFollowListPageSize,
    int offset = 0,
    bool forceRefresh = false,
  }) async =>
      _page(offset, limit);

  @override
  Future<List<FollowerListItem>> getFollowing(
    String userId, {
    int limit = kFollowListPageSize,
    int offset = 0,
    bool forceRefresh = false,
  }) async =>
      _page(offset, limit);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _PagedFollowRepo repo;
  late ProviderContainer container;

  ProviderContainer containerFor(int total) {
    repo = _PagedFollowRepo(total);
    return ProviderContainer(overrides: [
      followRepositoryProvider.overrideWithValue(repo),
    ]);
  }

  tearDown(() => container.dispose());

  test(
      'Given more followers than one page, When loadMore runs, '
      'Then the next page is appended at the right offset', () async {
    container = containerFor(kFollowListPageSize + 10);
    final first = await container.read(followersProvider('me').future);
    final notifier = container.read(followersProvider('me').notifier);

    expect(first, hasLength(kFollowListPageSize));
    expect(notifier.hasMore, isTrue);

    await notifier.loadMore();

    final all = container.read(followersProvider('me')).value!;
    expect(all, hasLength(kFollowListPageSize + 10));
    expect(all.map((u) => u.id).toSet(), hasLength(kFollowListPageSize + 10));
    expect(repo.offsets, [0, kFollowListPageSize]);
    expect(notifier.hasMore, isFalse);
  });

  test(
      'Given the whole list fits one page, When loadMore runs, '
      'Then no second request is sent', () async {
    container = containerFor(5);
    await container.read(followingProvider('me').future);
    final notifier = container.read(followingProvider('me').notifier);

    expect(notifier.hasMore, isFalse);
    await notifier.loadMore();

    expect(repo.offsets, [0]);
  });

  test(
      'Given a paged list, When refresh runs, '
      'Then it restarts from the first page', () async {
    container = containerFor(kFollowListPageSize * 2 + 1);
    await container.read(followersProvider('me').future);
    final notifier = container.read(followersProvider('me').notifier);
    await notifier.loadMore();

    await notifier.refresh();

    expect(container.read(followersProvider('me')).value, hasLength(kFollowListPageSize));
    expect(repo.offsets.last, 0);
    expect(notifier.hasMore, isTrue);
  });
}
