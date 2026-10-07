// features/auth/providers/auth_provider.dart — Auth state management.
//
// Why Riverpod?
//   - Compile-time safety: no runtime ProviderNotFoundException.
//   - Works outside of BuildContext (in interceptors, services, etc.).
//   - Simple async state with AsyncValue<T> — loading/data/error states
//     are first-class and don't require manual bool flags.
//
// authRepositoryProvider: supplies a singleton AuthRepository.
// authStateProvider: tracks whether the user is authenticated.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/push/push_service.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/feed/providers/feed_providers.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/profile/providers/user_locations_provider.dart';
import 'package:social_flutter/features/reports/data/report_repository.dart';
import 'package:social_flutter/features/search/providers/search_provider.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';

/// Provides the AuthRepository — the single instance for the app lifetime.
/// Receives both the main Dio (auth-aware) for login/register and the bare
/// Dio (no AuthInterceptor) for logout, so /auth/logout doesn't recurse
/// through the refresh-token flow with a possibly-expired access token.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(dio, bareDio);
});

/// Every keep-alive provider that holds one account's data. A family entry
/// resets every member at once.
///
/// Reset on sign-out AND on sign-in: seven of these used to be, so the next
/// account on the device saw the last one's follow requests, its "Unblock"
/// menu items, its star rating on the rate button, and — for private accounts
/// the previous user followed — profiles and trips it was never allowed. A
/// session that ended on the interceptor's forced path never ran sign-out at
/// all, which is why sign-in resets too.
final List<ProviderOrFamily> _userScopedProviders = [
  myProfileProvider,
  myItinerariesProvider,
  sharedWithMeProvider,
  savedItinerariesProvider,
  searchQueryProvider,
  notificationsProvider,
  notificationBadgeProvider,
  feedProvider,
  followRequestsProvider,
  followersProvider,
  followingProvider,
  blockedUsersProvider,
  userProfileProvider,
  userItinerariesProvider,
  userLocationsProvider,
  itineraryDetailProvider,
  myRatingProvider,
  ratingsPageProvider,
  editorsProvider,
  allowedUsersProvider,
  // Disposing each notifier also cancels its heartbeat timer.
  editLockProvider,
  // A translation is of something this account was allowed to read.
  translationConfigProvider,
  contentTranslationProvider,
];

void _resetUserScopedState(Ref ref) {
  for (final provider in _userScopedProviders) {
    ref.invalidate(provider);
  }
}

/// AuthState represents the authentication status.
/// null = not authenticated, non-null = authenticated user ID.
class AuthNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Initial state: null (not authenticated).
    // The router redirect checks secure storage directly on startup.
    return null;
  }

  /// Called after a successful login or register.
  void setAuthenticated(String userId) {
    // The tokens were written before we got here, but hasSessionProvider may
    // have cached the `false` it read on the login screen.
    ref.invalidate(hasSessionProvider);
    // A second account on the same device must inherit nothing the first left
    // behind — including its badge count, which the poller would then read as
    // a baseline and never correct upward.
    _resetUserScopedState(ref);
    state = userId;
  }

  /// Called on logout or when a 401 is received.
  Future<void> logout() async {
    // BEFORE the repository call, which discards the access token this needs.
    // Not optional: a device token that outlives the session keeps delivering
    // this user's notifications — including moderation notices — to whoever
    // signs in next on the same phone. Never throws.
    await unregisterForPush();
    // Same reason, same order: an unreleased claim blocks every other editor
    // until its TTL, and releasing needs the access token about to be discarded.
    await releaseAllEditClaims(ref);
    await ref.read(authRepositoryProvider).logout();
    // The disk cache is this account's responses — offline, the next person to
    // sign in would be served them (profile, private trips, notifications).
    try {
      await httpCacheStore?.clean();
    } catch (_) {
      // A cache that could not be wiped is still partitioned by account.
    }
    if (!ref.mounted) return;
    // Use invalidate() not refresh() — the user is unauthenticated at this
    // point, so a refetch would immediately 401.
    _resetUserScopedState(ref);
    // hasSessionProvider caches a storage read; without this it would still
    // report a live session after the tokens are gone.
    ref.invalidate(hasSessionProvider);
    state = null;
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, String?>(() => AuthNotifier());

/// True when a live refresh token is on the device.
///
/// The same signal the router redirect uses, and for the same reason: the
/// access token is short-lived and may legitimately be expired, while
/// authNotifierProvider is only set by an explicit login — a session restored
/// on cold launch leaves it null. Anything that needs "is somebody signed in?"
/// outside the router has to read storage, not that notifier.
final hasSessionProvider = FutureProvider<bool>((ref) async {
  // Tokens can be wiped where no ref exists (a rejected refresh, a suspension);
  // without this the provider kept saying "signed in" and the poller and the
  // ToS gate acted on a session that was gone.
  void onSessionEnded() => ref.invalidateSelf();
  sessionEnded.addListener(onSessionEnded);
  ref.onDispose(() => sessionEnded.removeListener(onSessionEnded));
  final refresh = await readRefreshToken();
  if (refresh == null || refresh.isEmpty) return false;
  final expiry = await readRefreshExpiresAt();
  return expiry == null || expiry.isAfter(DateTime.now());
});
