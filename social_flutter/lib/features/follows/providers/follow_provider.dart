// features/follows/providers/follow_provider.dart — Follow request state management.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';
import 'package:social_flutter/shared/models/follow.dart';

/// Provides the FollowRepository singleton.
final followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepository(dio);
});

/// Manages the list of pending incoming follow requests.
class FollowRequestsNotifier extends AsyncNotifier<List<FollowRequestItem>> {
  @override
  Future<List<FollowRequestItem>> build() async {
    return ref.read(followRepositoryProvider).getFollowRequests();
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    // Only a state with nothing to show swaps in the skeleton. A pull-to-refresh
    // draws its own spinner over a list the user is still holding, and blanking
    // it mid-gesture reads as the requests being wiped.
    if (!state.hasValue) state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(followRepositoryProvider)
          .getFollowRequests(forceRefresh: true),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }

  /// Reload in the background, leaving the current list on screen throughout.
  ///
  /// The screen calls this on open, because this provider is keep-alive: without
  /// it the second visit renders whatever the first one fetched, so a request
  /// that arrived in between is invisible until something else invalidates.
  /// Nobody asked for this load, so it may neither blank the list with a spinner
  /// nor replace it with an error — a failure just leaves the last good data.
  Future<void> silentRefresh() async {
    if (!isOnlineNowRef(ref)) return;

    // Called the moment the screen opens, which on a first visit is while
    // build() is still fetching the same list. Wait for the answer already on
    // the wire rather than racing it with an identical second request.
    if (!state.hasValue) {
      try {
        await future;
      } catch (_) {
        // build()'s failure is already the provider's state; nothing to add.
      }
      return;
    }

    final List<FollowRequestItem> rows;
    try {
      rows = await ref.read(followRepositoryProvider).getFollowRequests();
    } catch (_) {
      // Swallowed on purpose — see the doc comment. Pull-to-refresh is the loud
      // path if the user wants to know.
      return;
    }
    if (!ref.mounted) return;
    state = AsyncData(rows);
  }

  /// Optimistically remove a request from the list after accepting or rejecting.
  /// This gives immediate UI feedback without waiting for a server round-trip.
  void removeRequest(String followId) {
    state.whenData((requests) {
      state = AsyncData(
        requests.where((r) => r.followId != followId).toList(),
      );
    });
  }

  /// Accept a follow request, then remove it from the list.
  Future<void> acceptRequest(String followId) async {
    await ref.read(followRepositoryProvider).acceptFollowRequest(followId);
    removeRequest(followId);
  }

  /// Reject a follow request, then remove it from the list.
  Future<void> rejectRequest(String followId) async {
    await ref.read(followRepositoryProvider).rejectFollowRequest(followId);
    removeRequest(followId);
  }
}

final followRequestsProvider =
    AsyncNotifierProvider<FollowRequestsNotifier, List<FollowRequestItem>>(
  () => FollowRequestsNotifier(),
);

// ---------------------------------------------------------------------------
// Followers / Following list providers (family — one instance per userId)
// ---------------------------------------------------------------------------
//
// Why FamilyAsyncNotifier?
//   A "family" provider creates one independent cached instance per argument.
//   followersProvider('user-123') and followersProvider('user-456') are two
//   separate providers with separate state — they don't interfere with each other.
//   This is important so opening User A's followers list doesn't overwrite User B's.
//
// `arg` inside FamilyAsyncNotifier:
//   The userId passed to the provider (e.g., followersProvider(userId)) is
//   accessible as `arg` anywhere in the notifier class. We use it in refresh()
//   because the build() parameter is only available during the initial build.

/// One user's followers or following, a page at a time — the same offset
/// paging as FeedNotifier. The server caps a page, so without [loadMore] a
/// list silently stopped at its first page.
abstract class FollowListNotifier extends AsyncNotifier<List<FollowerListItem>> {
  FollowListNotifier(this.arg); // family argument: user id
  final String arg;

  int _offset = 0;
  // False until a full first page proves there may be more — so a subclass
  // that overrides build() never shows a loader for pages it cannot fetch.
  bool _hasMore = false;
  bool _loadingMore = false;

  /// Whether another page may exist — drives the trailing load-more indicator.
  bool get hasMore => _hasMore;

  Future<List<FollowerListItem>> fetchPage(int offset, {bool forceRefresh = false});

  List<FollowerListItem> _startFrom(List<FollowerListItem> firstPage) {
    _offset = firstPage.length;
    _hasMore = firstPage.length == kFollowListPageSize;
    return firstPage;
  }

  @override
  Future<List<FollowerListItem>> build() async => _startFrom(await fetchPage(0));

  /// Append the next page. No-op while a load is in flight or the end is reached.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.value;
    if (current == null) return;
    _loadingMore = true;
    try {
      final next = await fetchPage(_offset);
      if (!ref.mounted) return;
      _offset += next.length;
      _hasMore = next.length == kFollowListPageSize;
      // A follow arriving between pages shifts every row down one, so the
      // next page repeats the last one — skip ids already shown.
      final seen = {for (final user in current) user.id};
      state = AsyncData([...current, ...next.where((user) => !seen.contains(user.id))]);
    } catch (_) {
      // Called unawaited from a scroll listener: keep the rows already shown,
      // and the next scroll to the bottom retries.
    } finally {
      _loadingMore = false;
    }
  }

  /// Re-fetches page 0 and replaces the current state. Called by the
  /// RefreshIndicator (pull-to-refresh). Forces a fresh server fetch so a 304
  /// with the cached body can't silently no-op the refresh.
  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () async => _startFrom(await fetchPage(0, forceRefresh: true)),
    );
    if (!ref.mounted) return;
    state = next;
  }
}

/// Loads and caches the accepted followers list for a given user ID.
/// Returns a 403 error for private accounts the current user doesn't follow.
class FollowersNotifier extends FollowListNotifier {
  FollowersNotifier(super.arg);

  @override
  Future<List<FollowerListItem>> fetchPage(int offset, {bool forceRefresh = false}) =>
      ref.read(followRepositoryProvider).getFollowers(
            arg,
            offset: offset,
            forceRefresh: forceRefresh,
          );
}

final followersProvider =
    AsyncNotifierProvider.family<FollowersNotifier, List<FollowerListItem>, String>(
  FollowersNotifier.new,
);

/// Loads and caches the list of users that a given user follows.
/// Returns a 403 error for private accounts the current user doesn't follow.
class FollowingNotifier extends FollowListNotifier {
  FollowingNotifier(super.arg);

  @override
  Future<List<FollowerListItem>> fetchPage(int offset, {bool forceRefresh = false}) =>
      ref.read(followRepositoryProvider).getFollowing(
            arg,
            offset: offset,
            forceRefresh: forceRefresh,
          );
}

final followingProvider =
    AsyncNotifierProvider.family<FollowingNotifier, List<FollowerListItem>, String>(
  FollowingNotifier.new,
);
