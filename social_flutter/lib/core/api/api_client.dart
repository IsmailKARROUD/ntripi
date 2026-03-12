// core/api/api_client.dart — Dio HTTP client with authentication interceptor.
//
// Why Dio over http package?
//   - Built-in interceptor system: attach auth headers to every request
//     automatically without wrapping every call.
//   - Centralized error handling via interceptors.
//   - FormData support, progress callbacks, and cancellation tokens.
//
// The AuthInterceptor:
//   - On every request: reads the JWT from secure storage and adds the
//     Authorization header. This is transparent to all callers — they
//     never need to manually add the header.
//   - On 401 response: the token is invalid or expired. Clear it from
//     storage and redirect to the login screen. This prevents the user
//     from being stuck in a broken authenticated state.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';

/// Singleton Dio instance used throughout the app.
/// Lazily initialised via [createDioClient].
late final Dio dio;

/// Create and configure the Dio client.
/// Call this once in main() before runApp().
Dio createDioClient() {
  final instance = Dio(
    BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      // Always send/expect JSON.
      headers: {'Content-Type': 'application/json'},
    ),
  );

  instance.interceptors.add(AuthInterceptor());

  // In debug mode, log requests and responses for easier development.
  // Remove or disable in production builds.
  assert(() {
    instance.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ),
    );
    return true;
  }());

  return instance;
}

/// The navigation key that allows navigation from outside a widget context.
/// The router must set this to its [GoRouter]'s navigator key.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Interceptor that:
/// 1. Attaches the Bearer token to every outgoing request.
/// 2. On 401: clears the token and redirects to login.
class AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await readToken();
    if (token != null) {
      // Attach the token to the Authorization header.
      // The header value follows the Bearer token scheme from RFC 6750.
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options); // Continue with the modified request
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // The token is invalid or expired.
      // 1. Clear the stored token so we don't keep retrying with bad credentials.
      await deleteToken();

      // 2. Redirect to the login screen.
      // We use the navigator key because we're outside the widget tree here.
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.go('/login');
      }
    }
    // Pass the error along — the calling code can still inspect it.
    handler.next(err);
  }
}

/// Helper: extract the 'detail' string from a Dio error response.
/// The Ntripi API always returns {"detail": "..."} for errors.
/// Returns a generic fallback message if the format is unexpected.
String extractErrorMessage(DioException e) {
  try {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return data['detail']?.toString() ?? 'An error occurred.';
    }
  } catch (_) {}
  return 'An error occurred. Please try again.';
}
