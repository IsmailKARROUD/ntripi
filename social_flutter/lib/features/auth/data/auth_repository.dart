// features/auth/data/auth_repository.dart — Auth API calls.
//
// The repository pattern separates data access from UI logic.
// The provider layer calls repository methods; the repository handles HTTP.
//
// Token rotation (refresh) lives in TokenManager, not here — this file
// only handles the explicit user-initiated endpoints (login/register/logout).

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';

/// Payload returned by both register and login.
class AuthResult {
  final String accessToken;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String userId;
  final String username;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.userId,
    required this.username,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        refreshExpiresAt:
            DateTime.parse(json['refresh_expires_at'] as String),
        userId: json['user_id'] as String,
        username: json['username'] as String,
      );
}

class AuthRepository {
  /// `_bareDio` is used for /auth/logout so it doesn't recurse through the
  /// AuthInterceptor (which would attach a potentially-expired access token
  /// and trigger a refresh during logout).
  final Dio _dio;
  final Dio _bareDio;

  const AuthRepository(this._dio, this._bareDio);

  /// GET /auth/tos — fetch the current Terms of Service text.
  Future<Map<String, dynamic>> fetchTos() async {
    final response = await _dio.get(kTosEndpoint);
    return response.data as Map<String, dynamic>;
  }

  /// POST /auth/register
  /// On success, persists the token pair and returns the result.
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
    required bool tosAccepted,
  }) async {
    final response = await _dio.post(kRegisterEndpoint, data: {
      'username': username,
      'email': email,
      'password': password,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
      'tos_accepted': tosAccepted,
    });

    final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
    await saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      refreshExpiresAt: result.refreshExpiresAt,
    );
    return result;
  }

  /// POST /auth/login — accepts email or username as identifier.
  Future<AuthResult> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _dio.post(kLoginEndpoint, data: {
      'identifier': identifier,
      'password': password,
    });

    final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
    await saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      refreshExpiresAt: result.refreshExpiresAt,
    );
    return result;
  }

  /// POST /auth/logout — best-effort server-side revocation, then local wipe.
  /// Failures are swallowed: the user expects logout to "just work" even
  /// when offline. The refresh token will eventually expire server-side.
  Future<void> logout() async {
    final refresh = await readRefreshToken();
    if (refresh != null) {
      try {
        await _bareDio
            .post(kLogoutEndpoint, data: {'refresh_token': refresh})
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Silently ignore — local clear below still happens.
      }
    }
    await clearAllTokens();
  }
}
