// features/profile/providers/profile_provider.dart — Profile state providers.
//
// myProfileProvider: loads and caches the current user's own profile.
// userProfileProvider: loads a specific user's public profile by ID.
//
// Both use AsyncNotifier which provides AsyncValue<T> — automatically
// handling loading, data, and error states without manual bool flags.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/shared/models/user.dart';

/// Provides the ProfileRepository singleton.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(dio);
});

/// Loads and manages the current user's own profile.
class MyProfileNotifier extends AsyncNotifier<User> {
  @override
  Future<User> build() async {
    return ref.read(profileRepositoryProvider).getMyProfile();
  }

  /// Refresh from server (e.g., after editing the profile).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getMyProfile(),
    );
  }

  /// Optimistic update after editing the profile.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    bool? isPrivate,
  }) async {
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).updateMyProfile(
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            clearAvatarUrl: clearAvatarUrl,
            isPrivate: isPrivate,
          ),
    );
  }
}

final myProfileProvider =
    AsyncNotifierProvider<MyProfileNotifier, User>(() => MyProfileNotifier());

/// Loads a specific user's public profile by their ID.
/// We use a family provider so each user ID gets its own cached state.
class UserProfileNotifier extends FamilyAsyncNotifier<User, String> {
  @override
  Future<User> build(String userId) async {
    return ref.read(profileRepositoryProvider).getUserProfile(userId);
  }

  Future<void> refresh() async {
    final userId = arg;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getUserProfile(userId),
    );
  }

  /// Update follow state locally without a full reload (optimistic update).
  void updateFollowState({required bool isFollowing, required bool followIsPending}) {
    state.whenData((user) {
      state = AsyncData(user.copyWith(
        isFollowing: isFollowing,
        followIsPending: followIsPending,
        followersCount: isFollowing
            ? user.followersCount + 1
            : (user.followersCount > 0 ? user.followersCount - 1 : 0),
      ));
    });
  }
}

final userProfileProvider =
    AsyncNotifierProviderFamily<UserProfileNotifier, User, String>(
  () => UserProfileNotifier(),
);
