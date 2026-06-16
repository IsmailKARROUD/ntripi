// features/profile/providers/profile_provider.dart — Profile state providers.
//
// myProfileProvider: loads and caches the current user's own profile.
// userProfileProvider: loads a specific user's public profile by ID.
//
// Both use AsyncNotifier which provides AsyncValue<T> — automatically
// handling loading, data, and error states without manual bool flags.

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/shared/models/user.dart';

/// CachedNetworkImage / putFile key the entry by the absolute URL. The server
/// sometimes returns a relative path (filesystem backend) and sometimes an
/// absolute R2 URL — normalize before touching the cache.
String _resolveAbsoluteUrl(String url) =>
    url.startsWith('/') ? '$kApiBaseUrl$url' : url;

/// Drop any stale entry for [url] in our project-wide image cache and seed
/// it with the freshly uploaded [bytes]. The next `CachedNetworkImage(url)`
/// render reads from disk — no network roundtrip, no flash of the old image.
Future<void> _refreshImageCache(String url, Uint8List bytes) async {
  final absUrl = _resolveAbsoluteUrl(url);
  await CachedNetworkImage.evictFromCache(
    absUrl,
    cacheManager: NtripiImageCacheManager(),
  );
  await NtripiImageCacheManager().putFile(
    absUrl,
    bytes,
    fileExtension: 'jpg',
  );
}

/// Eviction-only variant — used after delete, when there are no fresh bytes
/// to seed. Prevents the in-memory ImageCache from briefly serving the old
/// avatar after the column was nulled.
Future<void> _evictImageCache(String? url) async {
  if (url == null) return;
  await CachedNetworkImage.evictFromCache(
    _resolveAbsoluteUrl(url),
    cacheManager: NtripiImageCacheManager(),
  );
}

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
    String? coverImageUrl,
    bool clearCoverImageUrl = false,
    bool? isPrivate,
    List<String>? passportCountries,
    bool passportCountriesChanged = false,
    String? residentCountry,
    bool clearResidentCountry = false,
    List<String>? languages,
    bool languagesChanged = false,
  }) async {
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).updateMyProfile(
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            clearAvatarUrl: clearAvatarUrl,
            coverImageUrl: coverImageUrl,
            clearCoverImageUrl: clearCoverImageUrl,
            isPrivate: isPrivate,
            passportCountries: passportCountries,
            passportCountriesChanged: passportCountriesChanged,
            residentCountry: residentCountry,
            clearResidentCountry: clearResidentCountry,
            languages: languages,
            languagesChanged: languagesChanged,
          ),
    );
  }

  /// Upload a new avatar image. State is updated with the returned URL
  /// (optimistic — no full reload). Throws on network/validation errors.
  Future<void> uploadAvatar(Uint8List bytes, String filename) async {
    final url = await ref
        .read(profileRepositoryProvider)
        .uploadAvatarImage(bytes: bytes, filename: filename);
    // Seed the local cache with the bytes we just uploaded so the next
    // render is instant (and not a roundtrip back to R2). Cross-device
    // freshness is handled by the ?v=<ts> the server appends to the URL.
    await _refreshImageCache(url, bytes);
    state.whenData((user) {
      state = AsyncData(user.copyWith(avatarUrl: url));
    });
  }

  /// Delete the avatar and refresh the profile from server (clean nullable state).
  Future<void> deleteAvatar() async {
    await _evictImageCache(state.valueOrNull?.avatarUrl);
    await ref.read(profileRepositoryProvider).deleteAvatarImage();
    await refresh();
  }

  /// Upload a new cover image. State is updated with the returned URL.
  Future<void> uploadCoverImage(Uint8List bytes, String filename) async {
    final url = await ref
        .read(profileRepositoryProvider)
        .uploadCoverImage(bytes: bytes, filename: filename);
    await _refreshImageCache(url, bytes);
    state.whenData((user) {
      state = AsyncData(user.copyWith(coverImageUrl: url));
    });
  }

  /// Delete the cover image and refresh from server.
  Future<void> deleteCoverImage() async {
    await _evictImageCache(state.valueOrNull?.coverImageUrl);
    await ref.read(profileRepositoryProvider).deleteCoverImage();
    await refresh();
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
