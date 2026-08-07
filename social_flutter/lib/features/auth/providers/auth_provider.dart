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
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/search/providers/search_provider.dart';

/// Provides the AuthRepository — the single instance for the app lifetime.
/// Receives both the main Dio (auth-aware) for login/register and the bare
/// Dio (no AuthInterceptor) for logout, so /auth/logout doesn't recurse
/// through the refresh-token flow with a possibly-expired access token.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(dio, bareDio);
});

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
    state = userId;
  }

  /// Called on logout or when a 401 is received.
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    // Clear cached user data so a subsequent login as a different account
    // doesn't briefly show the previous user's content.
    // Use invalidate() not refresh() — the user is unauthenticated at this
    // point, so a refetch would immediately 401.
    ref.invalidate(myProfileProvider);
    ref.invalidate(myItinerariesProvider);
    ref.invalidate(savedItinerariesProvider);
    ref.invalidate(searchQueryProvider);
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
  final refresh = await readRefreshToken();
  if (refresh == null || refresh.isEmpty) return false;
  final expiry = await readRefreshExpiresAt();
  return expiry == null || expiry.isAfter(DateTime.now());
});
