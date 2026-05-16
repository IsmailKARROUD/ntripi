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
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';

/// Singleton Dio instance used throughout the app.
/// Lazily initialised via [createDioClient].
late final Dio dio;

/// Per-request override that bypasses the dio_cache_interceptor's conditional
/// GET validator. The interceptor skips cache lookup, omits `If-None-Match`,
/// hits the network unconditionally, and stores the new response.
///
/// Use this for pull-to-refresh and error-state Retry — explicit user signals
/// that mean "ignore whatever I have locally, go to the server." Without it,
/// the request still carries `If-None-Match` and may come back as a 304
/// reusing the same local body, which feels like the refresh did nothing.
Options forceRefreshOptions() => Options(
      extra: const CacheOptions(
        store: null,
        policy: CachePolicy.refresh,
      ).toExtra(),
    );

/// Create and configure the Dio client.
/// Call this once in main() before runApp().
///
/// [cacheStore] persists GET responses so the app remains browsable while
/// offline. Pass null only when caching is intentionally disabled (tests).
Dio createDioClient({CacheStore? cacheStore}) {
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

  if (cacheStore != null) {
    // Cache GET responses. The backend's ETagMiddleware emits
    // `Cache-Control: private, no-cache` + an opaque ETag on every JSON GET,
    // so the `request` policy works as intended: the interceptor stores
    // responses, sends `If-None-Match` on the next request, and the server
    // can reply with a tiny `304 Not Modified` when the body is unchanged.
    // On any Dio error (offline / timeout) the most recent cached entry is
    // returned, keeping previously-viewed screens readable without a
    // connection.
    instance.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: cacheStore,
          policy: CachePolicy.request,
          hitCacheOnErrorExcept: const [],
          maxStale: const Duration(days: 7),
          priority: CachePriority.normal,
          keyBuilder: CacheOptions.defaultCacheKeyBuilder,
        ),
      ),
    );
  }

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
      final path = options.path;
      final isAuthEndpoint = path == kLoginEndpoint || path == kRegisterEndpoint;

      if (isJwtExpired(token)) {
        await deleteToken();
        // Auth endpoints don't need a valid token — let the request through
        // so the login/register screen can complete. Only redirect on
        // protected routes, otherwise the first login after an expired
        // session is cancelled before it reaches the server.
        if (!isAuthEndpoint) {
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
      } else {
        // Attach the token to the Authorization header.
        // The header value follows the Bearer token scheme from RFC 6750.
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
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
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'No internet connection. Please check your network and try again.';
      default:
        break;
    }
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
