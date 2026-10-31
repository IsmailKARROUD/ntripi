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
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/cache/image_cache.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/providers/reload_keeps_content.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/domain/violation.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

/// Drop any stale entry for [url] in our project-wide image cache and seed
/// it with the freshly uploaded [bytes]. The next `CachedNetworkImage(url)`
/// render reads from disk — no network roundtrip, no flash of the old image.
Future<void> _refreshImageCache(String url, Uint8List bytes) async {
  // CachedNetworkImage and putFile key the entry by the absolute URL.
  final absUrl = absoluteImageUrl(url);
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
    absoluteImageUrl(url),
    cacheManager: NtripiImageCacheManager(),
  );
}

/// Provides the ProfileRepository singleton.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(dio);
});

/// Loads and manages the current user's own profile.
class MyProfileNotifier extends AsyncNotifier<User>
    with ReloadKeepsContent<User> {
  @override
  Future<User> build() async {
    return ref.read(profileRepositoryProvider).getMyProfile();
  }

  /// Pull-to-refresh and Retry: the profile stays on screen while it reloads.
  Future<ReloadFailure?> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return null;
    return reloadKeepingContent(
      () => ref.read(profileRepositoryProvider).getMyProfile(forceRefresh: true),
    );
  }

  /// A write answered with the whole profile (accepting the terms): it is the
  /// state, as a GET of /users/me would give it.
  void adopt(User user) {
    if (!ref.mounted) return;
    state = AsyncData(user);
  }

  /// A follow write answered with this account's counts — the server's, read
  /// after its commit. Never a local ±1, which would count twice from a stale
  /// row.
  void adoptCounts(UserCounts counts) {
    if (!ref.mounted) return;
    if (state case AsyncData(:final value)) {
      state = AsyncData(value.copyWith(
        followersCount: counts.followersCount,
        followingCount: counts.followingCount,
      ));
    }
  }

  /// Save a profile edit: the answer is the whole profile, and becomes the
  /// state. A refusal throws for the caller to show and leaves the profile —
  /// and the edit form drawn over it, typed text included — as it was.
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
    final user = await ref.read(profileRepositoryProvider).updateMyProfile(
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
        );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = AsyncData(user);
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
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((user) {
      state = AsyncData(user.copyWith(avatarUrl: url));
    });
  }

  /// Delete the avatar. Updates the state in place — never refresh() here: the
  /// delete changes nothing but the avatar URL, and the app never re-downloads
  /// after its own write.
  Future<void> deleteAvatar() async {
    await _evictImageCache(state.value?.avatarUrl);
    if (!ref.mounted) return; // disposed mid-request (logout)
    await ref.read(profileRepositoryProvider).deleteAvatarImage();
    if (!ref.mounted) return; // disposed mid-request (logout)
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
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((user) {
      state = AsyncData(user.copyWith(coverImageUrl: url));
    });
  }

  /// Delete the cover image. Updates the state in place — see deleteAvatar
  /// for why refresh() is not used here.
  Future<void> deleteCoverImage() async {
    await _evictImageCache(state.value?.coverImageUrl);
    if (!ref.mounted) return; // disposed mid-request (logout)
    await ref.read(profileRepositoryProvider).deleteCoverImage();
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((user) {
      state = AsyncData(user.copyWith(clearCoverImageUrl: true));
    });
  }
}

final myViolationsProvider =
    AsyncNotifierProvider.autoDispose<MyViolationsNotifier, List<Violation>>(
  MyViolationsNotifier.new,
);

/// Moderation actions taken against the current user (Account status screen).
class MyViolationsNotifier extends AsyncNotifier<List<Violation>>
    with ReloadKeepsContent<List<Violation>> {
  @override
  Future<List<Violation>> build() =>
      ref.read(profileRepositoryProvider).getViolations();

  /// Pull-to-refresh: the list stays on screen while it reloads.
  Future<ReloadFailure?> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return null;
    return reloadKeepingContent(
      () => ref.read(profileRepositoryProvider).getViolations(forceRefresh: true),
    );
  }

  /// An appeal answered with the list as it now stands, its row marked
  /// pending — so the screen shows it without downloading the list again.
  void adopt(List<Violation> violations) {
    if (!ref.mounted) return;
    state = AsyncData(violations);
  }
}

final myProfileProvider =
    AsyncNotifierProvider<MyProfileNotifier, User>(() => MyProfileNotifier());

/// [MyProfileNotifier.adoptCounts] where the profile is loaded. Reading the
/// notifier of one that is not would build it — the GET this replaces.
void adoptMyCounts(ProviderContainer container, UserCounts counts) {
  if (container.exists(myProfileProvider)) {
    container.read(myProfileProvider.notifier).adoptCounts(counts);
  }
}

/// [UserProfileNotifier.updateFollowState] on [userId]'s profile, where it is
/// loaded — for the same reason as [adoptMyCounts].
void adoptTheirFollowState(
  ProviderContainer container,
  String userId, {
  bool? isFollowing,
  bool? followIsPending,
  bool? followsYou,
  UserCounts? counts,
}) {
  final profile = userProfileProvider(userId);
  if (container.exists(profile)) {
    container.read(profile.notifier).updateFollowState(
          isFollowing: isFollowing,
          followIsPending: followIsPending,
          followsYou: followsYou,
          counts: counts,
        );
  }
}

/// Loads a specific user's public profile by their ID.
/// We use a family provider so each user ID gets its own cached state.
class UserProfileNotifier extends AsyncNotifier<User>
    with ReloadKeepsContent<User> {
  UserProfileNotifier(this.arg); // family argument: user id
  final String arg;

  @override
  Future<User> build() async {
    return ref.read(profileRepositoryProvider).getUserProfile(arg);
  }

  /// Pull-to-refresh: the profile stays on screen while it reloads, unless
  /// the account is gone or blocked (404), which replaces it.
  Future<ReloadFailure?> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return null;
    return reloadKeepingContent(
      () => ref
          .read(profileRepositoryProvider)
          .getUserProfile(arg, forceRefresh: true),
    );
  }

  /// A follow write between us changed this profile: the follow state it
  /// left, and this account's counts as its answer carried them — the
  /// server's, never a local ±1. Null leaves a field as it was.
  void updateFollowState({
    bool? isFollowing,
    bool? followIsPending,
    bool? followsYou,
    UserCounts? counts,
  }) {
    if (!ref.mounted) return;
    state.whenData((user) {
      state = AsyncData(user.copyWith(
        isFollowing: isFollowing,
        followIsPending: followIsPending,
        followsYou: followsYou,
        followersCount: counts?.followersCount,
        followingCount: counts?.followingCount,
      ));
    });
  }
}

final userProfileProvider =
    AsyncNotifierProvider.family<UserProfileNotifier, User, String>(
  UserProfileNotifier.new,
);

/// The account id behind a handle, for a shared profile link — GET
/// /users/{identifier} takes a handle as well as an id, 404ing alike for an
/// unknown, deleted or suspended account and across a block. AutoDispose: it is
/// needed once per link, and the answer depends on who asks, so it must not
/// outlive the screen — or the session.
final profileIdByUsernameProvider =
    FutureProvider.autoDispose.family<String, String>((ref, username) async {
  final user =
      await ref.read(profileRepositoryProvider).getUserProfile(username);
  return user.id;
});
