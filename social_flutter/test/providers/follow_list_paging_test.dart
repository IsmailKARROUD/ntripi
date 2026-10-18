// test/providers/follow_list_paging_test.dart — the followers / following
// lists page through the whole set instead of stopping at the server's first
// page (which is what made a 150-follower account show 20).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/shared/models/follow.dart';

/// Serves [total] users in pages of [kFollowListPageSize] and records every
/// offset it was asked for.
class _PagedFollowRepo implements FollowRepository {
  _PagedFollowRepo(this.total);
  final int total;
  final List<int> offsets = [];

  /// Ids the server no longer lists — a follower removed between pages.
  final Set<String> gone = {};

  /// When set, a followers page is computed at request time but delivered
  /// only once this completes: an answer already on the wire.
  Completer<void>? gate;

  List<FollowerListItem> _page(int offset, int limit) {
    offsets.add(offset);
    final all = [
      for (var i = 0; i < total; i++)
        if (!gone.contains('u$i'))
          FollowerListItem(id: 'u$i', username: 'user$i', isPrivate: false),
    ];
    return all.sublist(
      offset.clamp(0, all.length),
      (offset + limit).clamp(0, all.length),
    );
  }

  @override
  Future<List<FollowerListItem>> getFollowers(
    String userId, {
    int limit = kFollowListPageSize,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final page = _page(offset, limit);
    await gate?.future;
    return page;
  }

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

  // ── removeLocally: a row the server removed (Remove / Unfollow) ────────

  test(
      'Given a loaded page, When a row is removed, '
      'Then the next page starts one row earlier and skips no one', () async {
    container = containerFor(kFollowListPageSize + 10);
    await container.read(followersProvider('me').future);
    final notifier = container.read(followersProvider('me').notifier);

    notifier.removeLocally('u3');
    repo.gone.add('u3'); // the server's list shrank before the offset too
    await notifier.loadMore();

    final ids = container
        .read(followersProvider('me'))
        .value!
        .map((u) => u.id)
        .toList();
    expect(repo.offsets.last, kFollowListPageSize - 1);
    // The row that slid into the gap — skipped by an offset left at 50.
    expect(ids, contains('u$kFollowListPageSize'));
    expect(ids, isNot(contains('u3')));
    expect(ids.toSet(), hasLength(kFollowListPageSize + 10 - 1));
  });

  test(
      'Given a row past the loaded pages, When it is removed, '
      'Then the offset is left alone', () async {
    container = containerFor(kFollowListPageSize + 10);
    await container.read(followersProvider('me').future);
    final notifier = container.read(followersProvider('me').notifier);

    notifier.removeLocally('u55'); // not loaded: nothing to drop, nothing shifts
    repo.gone.add('u55');
    await notifier.loadMore();

    final ids = container
        .read(followersProvider('me'))
        .value!
        .map((u) => u.id)
        .toList();
    expect(repo.offsets.last, kFollowListPageSize);
    expect(ids.toSet(), hasLength(kFollowListPageSize + 10 - 1));
  });

  test(
      'Given a page on the wire, When a row is removed meanwhile, '
      'Then the page that lands does not bring it back', () async {
    container = containerFor(kFollowListPageSize + 10);
    await container.read(followersProvider('me').future);
    final notifier = container.read(followersProvider('me').notifier);

    repo.gate = Completer<void>();
    final loading = notifier.loadMore();
    notifier.removeLocally('u3');
    repo.gate!.complete();
    await loading;

    final ids = container
        .read(followersProvider('me'))
        .value!
        .map((u) => u.id)
        .toList();
    expect(ids, isNot(contains('u3')));
    expect(ids, hasLength(kFollowListPageSize + 10 - 1));
  });
}
