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
import 'package:social_flutter/features/auth/data/auth_repository.dart';

/// Provides the AuthRepository — the single instance for the app lifetime.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(dio);
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
    state = userId;
  }

  /// Called on logout or when a 401 is received.
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = null;
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, String?>(() => AuthNotifier());
