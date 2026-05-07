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
import 'package:flutter/widgets.dart';
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
/// 2. On 401 from a protected route: clears the token and redirects to login.
///    Auth endpoints (/auth/login, /auth/register) are excluded — they can
///    legitimately return 401 (wrong credentials) and the screen handles that
///    error inline. Redirecting here would rebuild the screen before the
///    catch block can display the message.
class AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await readToken();
    if (token != null) {
      if (isJwtExpired(token)) {
        // Evict the stale token and redirect to login without hitting the network.
        await deleteToken();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) ctx.go('/login');
        });
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          message: 'session_expired',
        ));
        return;
      }
      // Attach the token to the Authorization header.
      // The header value follows the Bearer token scheme from RFC 6750.
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options); // Continue with the modified request
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Skip the redirect for auth endpoints — their 401 means "wrong credentials"
      // and the LoginScreen / RegisterScreen will display the error themselves.
      final path = err.requestOptions.path;
      final isAuthEndpoint = path == kLoginEndpoint || path == kRegisterEndpoint;

      if (!isAuthEndpoint) {
        // A protected route returned 401: clear the token, then navigate to login.
        // We use .then() instead of async/await because Dio does not properly
        // await async onError callbacks — using async here causes a race where
        // handler.next() is never called, hanging the request.
        // addPostFrameCallback defers the navigation until after the current
        // build frame, avoiding "setState during build" errors.
        deleteToken().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              ctx.go('/login');
            }
          });
        });
      }
    }
    // Always resolve the handler so the Dio future completes.
    handler.next(err);
  }
}

/// Helper: extract a human-readable message from any exception.
/// For DioException, reads the API's {"detail": "..."} response body.
/// For ItineraryStaleException and other typed exceptions, uses toString().
String extractErrorMessage(dynamic e) {
  if (e is DioException) {
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        return data['detail']?.toString() ?? 'An error occurred.';
      }
    } catch (_) {}
    return 'An error occurred. Please try again.';
  }
  return e?.toString() ?? 'An error occurred.';
}
