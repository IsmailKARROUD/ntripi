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
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/features/profile/domain/violation.dart';
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
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getMyProfile(),
    );
  }

  /// Optimistic update after editing the profile.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    bool? isPrivate,
    List<String>? passportCountries,
    bool passportCountriesChanged = false,
    String? residentCountry,
    bool clearResidentCountry = false,
    List<String>? languages,
    bool languagesChanged = false,
    bool? notifyRatings,
    bool? notifySaves,
    bool? notifyFollowAccepted,
  }) async {
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).updateMyProfile(
            displayName: displayName,
            bio: bio,
            isPrivate: isPrivate,
            passportCountries: passportCountries,
            passportCountriesChanged: passportCountriesChanged,
            residentCountry: residentCountry,
            clearResidentCountry: clearResidentCountry,
            languages: languages,
            languagesChanged: languagesChanged,
            notifyRatings: notifyRatings,
            notifySaves: notifySaves,
            notifyFollowAccepted: notifyFollowAccepted,
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

  /// Delete the avatar. Updates state optimistically — do NOT call refresh()
  /// here. refresh() sets state to AsyncLoading, which makes
  /// profile_screen.dart's `profileAsync.when(loading: ..., data: ...)` rip
  /// the ProfileEditForm out of the widget tree mid-_saveEdits. The form's
  /// State gets disposed, `mounted` becomes false, and the onSaved callback
  /// that closes the form never fires.
  Future<void> deleteAvatar() async {
    await _evictImageCache(state.value?.avatarUrl);
    await ref.read(profileRepositoryProvider).deleteAvatarImage();
    state.whenData((user) {
      state = AsyncData(user.copyWith(clearAvatarUrl: true));
    });
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

  /// Delete the cover image. Optimistic local update — see deleteAvatar for
  /// the reason refresh() must NOT be used here.
  Future<void> deleteCoverImage() async {
    await _evictImageCache(state.value?.coverImageUrl);
    await ref.read(profileRepositoryProvider).deleteCoverImage();
    state.whenData((user) {
      state = AsyncData(user.copyWith(clearCoverImageUrl: true));
    });
  }
}

final myProfileProvider =
    AsyncNotifierProvider<MyProfileNotifier, User>(() => MyProfileNotifier());

/// Moderation actions taken against the current user (Account status screen).
/// Invalidate after filing an appeal so the row's state refreshes.
final myViolationsProvider = FutureProvider.autoDispose<List<Violation>>((ref) {
  return ref.read(profileRepositoryProvider).getViolations();
});

/// Loads a specific user's public profile by their ID.
/// We use a family provider so each user ID gets its own cached state.
class UserProfileNotifier extends AsyncNotifier<User> {
  UserProfileNotifier(this.arg); // family argument: user id
  final String arg;

  @override
  Future<User> build() async {
    return ref.read(profileRepositoryProvider).getUserProfile(arg);
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    final userId = arg;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getUserProfile(userId),
    );
  }

  /// Update follow state locally without a full reload (optimistic update).
  void updateFollowState({required bool isFollowing, required bool followIsPending}) {
    state.whenData((user) {
      // Only accepted-follow transitions move the count — a pending request or
      // its cancellation must leave the target's followers count untouched.
      final delta = (isFollowing && !user.isFollowing)
          ? 1
          : (!isFollowing && user.isFollowing)
              ? -1
              : 0;
      state = AsyncData(user.copyWith(
        isFollowing: isFollowing,
        followIsPending: followIsPending,
        followersCount:
            (user.followersCount + delta).clamp(0, 1 << 31).toInt(),
      ));
    });
  }
}

final userProfileProvider =
    AsyncNotifierProvider.family<UserProfileNotifier, User, String>(
  UserProfileNotifier.new,
);
