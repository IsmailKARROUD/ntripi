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
