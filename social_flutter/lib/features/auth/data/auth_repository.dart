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

  /// GET /auth/tos — the Terms of Service, the Community Guidelines AND the
  /// Privacy Policy, in one response so the signup screen can show any of them
  /// without a second call. `lang` picks the translation; the server falls back
  /// to English for anything it does not have.
  Future<Map<String, dynamic>> fetchTos({String? lang}) async {
    final response = await _dio.get(
      kTosEndpoint,
      queryParameters: lang == null ? null : {'lang': lang},
    );
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

  /// POST /auth/google — exchange a Google ID token for a Ntripi token pair.
  /// Serves sign-in, sign-up, AND verifying an existing account: the backend
  /// links by matching email and returns a fresh pair for the same user.
  ///
  /// `tosAccepted` defaults false. Only the create-a-new-account branch reads
  /// it, and it answers 400 `tos_required` — the caller shows the agreement and
  /// retries with true. Signing in or linking never consults it, so a returning
  /// user is not re-prompted.
  Future<AuthResult> loginWithGoogle({
    required String idToken,
    bool tosAccepted = false,
  }) async {
    final response = await _dio.post(kGoogleAuthEndpoint, data: {
      'id_token': idToken,
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

  /// POST /auth/accept-tos — record acceptance of the ToS revision now in
  /// force. Takes no body: the server stamps its own TOS_VERSION, so a client
  /// cannot claim acceptance of a document it never rendered.
  Future<void> acceptTos() async {
    await _dio.post(kAcceptTosEndpoint);
  }

  /// POST /auth/forgot-password — ask the server to email a reset link.
  /// Enumeration-safe (always succeeds). Uses `_bareDio` since it's called
  /// from the login screen while logged out (no token to attach).
  Future<void> forgotPassword({required String email}) async {
    await _bareDio.post(kForgotPasswordEndpoint, data: {'email': email});
  }

  /// POST /auth/resend-verification — re-send the verify link to the signed-in
  /// user (the AuthInterceptor attaches the Bearer token).
  Future<void> resendVerification() async {
    await _dio.post(kResendVerificationEndpoint);
  }

  /// POST /auth/change-password — change the signed-in user's password.
  /// The server revokes all other sessions and returns a fresh token pair for
  /// THIS device; we persist it so the current session stays authenticated.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _dio.post(kChangePasswordEndpoint, data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });

    final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
    await saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      refreshExpiresAt: result.refreshExpiresAt,
    );
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
