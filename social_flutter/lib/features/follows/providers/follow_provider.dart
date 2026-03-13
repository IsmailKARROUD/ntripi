// features/follows/providers/follow_provider.dart — Follow request state management.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
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
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(followRepositoryProvider).getFollowRequests(),
    );
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

/// Loads and caches the accepted followers list for a given user ID.
/// Returns a 403 error for private accounts the current user doesn't follow.
class FollowersNotifier extends FamilyAsyncNotifier<List<FollowerListItem>, String> {
  @override
  Future<List<FollowerListItem>> build(String userId) {
    // `userId` here is the same as `arg` — Riverpod passes it as a parameter
    // on the initial build only. Use `arg` in all other methods.
    return ref.read(followRepositoryProvider).getFollowers(userId);
  }

  /// Re-fetches from the server and replaces the current state.
  /// Called by the RefreshIndicator (pull-to-refresh).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(followRepositoryProvider).getFollowers(arg),
    );
  }
}

final followersProvider =
    AsyncNotifierProviderFamily<FollowersNotifier, List<FollowerListItem>, String>(
  () => FollowersNotifier(),
);

/// Loads and caches the list of users that a given user follows.
/// Returns a 403 error for private accounts the current user doesn't follow.
class FollowingNotifier extends FamilyAsyncNotifier<List<FollowerListItem>, String> {
  @override
  Future<List<FollowerListItem>> build(String userId) {
    return ref.read(followRepositoryProvider).getFollowing(userId);
  }

  /// Re-fetches from the server and replaces the current state.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(followRepositoryProvider).getFollowing(arg),
    );
  }
}

final followingProvider =
    AsyncNotifierProviderFamily<FollowingNotifier, List<FollowerListItem>, String>(
  () => FollowingNotifier(),
);
