// features/auth/data/auth_repository.dart — Auth API calls.
//
// The repository pattern separates data access from UI logic.
// The provider layer calls repository methods; the repository handles HTTP.
// This makes it easy to swap implementations (e.g., for testing with mocks).

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';

/// Payload returned by both register and login.
class AuthResult {
  final String accessToken;
  final String userId;
  final String username;

  const AuthResult({
    required this.accessToken,
    required this.userId,
    required this.username,
  });
}

class AuthRepository {
  final Dio _dio;

  const AuthRepository(this._dio);

  /// GET /auth/tos — fetch the current Terms of Service text.
  Future<Map<String, dynamic>> fetchTos() async {
    final response = await _dio.get(kTosEndpoint);
    return response.data as Map<String, dynamic>;
  }

  /// POST /auth/register
  /// On success, saves the token and returns the result.
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

    final result = AuthResult(
      accessToken: response.data['access_token'] as String,
      userId: response.data['user_id'] as String,
      username: response.data['username'] as String,
    );

    // Persist the token immediately so subsequent API calls are authenticated.
    await saveToken(result.accessToken);
    return result;
  }

  /// POST /auth/login
  /// On success, saves the token and returns the result.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(kLoginEndpoint, data: {
      'email': email,
      'password': password,
    });

    final result = AuthResult(
      accessToken: response.data['access_token'] as String,
      userId: response.data['user_id'] as String,
      username: response.data['username'] as String,
    );

    await saveToken(result.accessToken);
    return result;
  }

  /// Clear the token (logout).
  Future<void> logout() async {
    await deleteToken();
  }
}
