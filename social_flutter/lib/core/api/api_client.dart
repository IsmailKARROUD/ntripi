// core/api/api_client.dart — Dio HTTP client with authentication interceptor.
//
// Why Dio over http package?
//   - Built-in interceptor system: attach auth headers to every request
//     automatically without wrapping every call.
//   - Centralized error handling via interceptors.
//   - FormData support, progress callbacks, and cancellation tokens.
//
// Four interceptors are installed, in this registration order:
//   1. AuthInterceptor    — attaches Bearer token, refreshes on expiry,
//                           retries once on 401.
//   2. DioCacheInterceptor — stores GET responses; serves stale on errors,
//                           except for kNeverServeStaleFor.
//   3. CacheEvictInterceptor — deletes entries the server says are gone.
//   4. LogInterceptor     — debug-only.
//
// The AuthInterceptor delegates ALL token decisions to TokenManager. The
// interceptor only knows three things: (a) attach a header, (b) what to do
// on 401, (c) what to do when refresh fails. The actual refresh / expiry /
// dedup logic lives in TokenManager — keep it that way.

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/api/api_error_codes.dart';
import 'package:social_flutter/core/api/cache_evict_interceptor.dart';
import 'package:social_flutter/core/auth/token_manager.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Singleton Dio instance used throughout the app.
/// Lazily initialised via [createDioClient].
late final Dio dio;

/// Bare Dio with no AuthInterceptor — used by TokenManager for /auth/refresh
/// (calling /auth/refresh through the AuthInterceptor would recurse) and by
/// AuthRepository for /auth/logout. Initialised alongside [dio] in main.dart.
late final Dio bareDio;

/// Marker on `RequestOptions.extra` set by the AuthInterceptor when an
/// expired-token request is allowed through unauthenticated because we're
/// offline. The cache layer can use this to prefer stale over the eventual
/// 401 from the server. Not currently consumed by anything (the cache
/// interceptor's existing offline behaviour suffices), but the flag is set
/// so future cache logic can read it.
const kAuthSkippedExtra = 'ntripi_auth_skipped';

/// Status codes that must never be answered from the cache.
///
/// dio_cache_interceptor reads this as "hit cache on error EXCEPT these", so an
/// empty list — the old value — meant a 404 for a blocked or deleted account was
/// silently replaced by the last profile we cached for that URL. Every code here
/// is the server saying "you may not see this"; serving the old body back is a
/// privacy bug, not a resilience feature.
///
/// Offline is unaffected: a connection error carries no `Response`, which the
/// interceptor handles in an earlier branch that always falls back to cache.
const List<int> kNeverServeStaleFor = [401, 403, 404, 410];


/// Per-request override that bypasses the dio_cache_interceptor's conditional
/// GET validator — used for pull-to-refresh / Retry. See original comments.
Options forceRefreshOptions() => Options(
      extra: const CacheOptions(
        store: null,
        policy: CachePolicy.refresh,
        // Per-request options REPLACE the interceptor's globals — restate the
        // stale-on-error fallback or offline/captive-portal refreshes error
        // out instead of re-serving the cached response. Keep this list in
        // step with createDioClient's.
        hitCacheOnErrorExcept: kNeverServeStaleFor,
        maxStale: Duration(days: 7),
      ).toExtra(),
    );

/// Build a bare Dio (no AuthInterceptor, no cache) — used internally for
/// refresh and logout.
Dio createBareDio() {
  return Dio(
    BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );
}

/// Create and configure the main Dio client.
/// Call this once in main() before runApp().
Dio createDioClient({
  required TokenManager tokenManager,
  CacheStore? cacheStore,
}) {
  final instance = Dio(
    BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // The interceptor needs a Dio that DOESN'T have AuthInterceptor for the
  // retry-after-refresh path — otherwise we'd deadlock on Dio's
  // interceptor lock (the outer interceptor awaits the retry, the retry
  // queues behind the outer interceptor). bareDio is the natural choice.
  instance.interceptors.add(AuthInterceptor(tokenManager, bareDio));

  if (cacheStore != null) {
    instance.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: cacheStore,
          policy: CachePolicy.request,
          hitCacheOnErrorExcept: kNeverServeStaleFor,
          maxStale: const Duration(days: 7),
          priority: CachePriority.normal,
          keyBuilder: CacheOptions.defaultCacheKeyBuilder,
        ),
      ),
    );
    // After the cache interceptor, so it only ever sees errors the cache layer
    // declined to answer.
    instance.interceptors.add(CacheEvictInterceptor(cacheStore));
  }

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

void _goToLogin() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) ctx.go('/login');
  });
}

void _goToSuspended() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) ctx.go('/suspended');
  });
}

/// Backend code returned on every request from a moderator-suspended account.
const kAccountDeactivatedCode = 'account_deactivated';

/// Backend code for "this signup needs an explicit ToS acceptance". Returned by
/// POST /auth/register and, for a brand-new account only, POST /auth/google.
const kTosRequiredCode = 'tos_required';

bool _isAuthEndpoint(String path) {
  return path == kLoginEndpoint ||
      path == kRegisterEndpoint ||
      path == kRefreshEndpoint ||
      path == kLogoutEndpoint;
}

/// Interceptor that:
/// 1. Attaches a (refreshed-if-needed) Bearer token to every outgoing request.
/// 2. On 401 from a protected route, attempts one transparent refresh-and-retry.
/// 3. On hard auth failure (refresh rejected by server), redirects to /login.
/// 4. On network failure during refresh, lets the request through unauthenticated
///    so the cache layer can serve stale content — does NOT log the user out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenManager, this._retryDio);

  final TokenManager _tokenManager;

  /// Dio used to replay the original request after a successful refresh.
  /// Must NOT have AuthInterceptor installed — calling fetch on the same
  /// Dio whose interceptor we're currently inside deadlocks on Dio's
  /// internal lock (the retry queues behind the in-flight onError).
  final Dio _retryDio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAuthEndpoint(options.path)) {
      handler.next(options);
      return;
    }

    try {
      final token = await _tokenManager.getValidAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    } on NetworkUnavailableException {
      // Offline + expired access token: let the request fly without auth.
      // It will fail with a 401 (or 0/network error) and the cache layer
      // serves the most recent stored response. We do NOT delete tokens
      // or navigate — the session is still potentially alive.
      options.extra[kAuthSkippedExtra] = true;
      handler.next(options);
    } on SessionExpiredException {
      // Refresh token rejected by the server — session is dead.
      _goToLogin();
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          message: 'session_expired',
        ),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;

    // A moderator suspension is enforced on every request (401 or 403 with this
    // code), so it must be caught before both the 401-only filter below and the
    // coded-error passthrough — otherwise a banned user just sees a generic
    // error on whatever screen they were on. Tokens are cleared here rather
    // than via AuthNotifier: an interceptor has no Riverpod ref.
    final body = err.response?.data;
    if ((status == 401 || status == 403) &&
        body is Map &&
        body['code'] == kAccountDeactivatedCode) {
      await clearAllTokens();
      _goToSuspended();
      handler.next(err);
      return;
    }

    if (status != 401 || _isAuthEndpoint(path)) {
      handler.next(err);
      return;
    }

    // Application-level 401s (wrong password, Google re-auth required, …) carry
    // an error `code`; only genuine access-token failures from get_current_user
    // are codeless. Don't refresh/retry/logout on these — let the caller surface
    // the message (otherwise a wrong-password 401 would bounce the user to /login).
    final data = err.response?.data;
    if (data is Map && data['code'] is String) {
      handler.next(err);
      return;
    }

    // Server rejected our access token mid-flight (token was valid by
    // local check but revoked server-side, or `exp` slipped past during
    // the request). Try one refresh + retry, then give up.
    try {
      final newAccess = await _tokenManager.forceRefresh();
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccess';
      // Fire the retry on _retryDio (no AuthInterceptor) so we don't
      // recurse — and to avoid Dio's interceptor lock deadlocking against
      // the onError that's currently awaiting us.
      final response = await _retryDio.fetch(retryOptions);
      handler.resolve(response);
      return;
    } on SessionExpiredException {
      // TokenManager has already cleared storage — just navigate.
      _goToLogin();
    } on NetworkUnavailableException {
      // Couldn't refresh, but session may still be alive — don't logout.
    } catch (_) {
      // Retry itself failed (e.g. another 401) — bail to login.
      _goToLogin();
    }

    handler.next(err);
  }
}

/// Returns the backend `code` string from a DioException error body, or null.
/// Lets callers branch on a specific backend error (e.g. surface the real AWS
/// moderation reason instead of a generic "upload failed" message).
String? apiErrorCode(dynamic e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      if (code is String) return code;
    }
  }
  return null;
}

/// Helper: extract a human-readable message from any exception.
String extractErrorMessage(dynamic e, [AppLocalizations? l10n]) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return l10n?.errorNoInternet ??
            'No internet connection. Please check your network and try again.';
      default:
        break;
    }
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        // Prefer the localized message for a known backend `code`; fall back to
        // the server's human `detail`, then a generic message.
        final code = data['code'];
        if (code is String && l10n != null) {
          // A moderation rejection ships the triggering categories alongside
          // the code. Turning them into a plain-language reason here means
          // every compose form explains itself without a per-form branch —
          // and none of them clear the field, so the text survives the error.
          if (code == 'text_moderation_rejected') {
            return moderationRejectionMessage(moderationCategories(e), l10n);
          }
          final localized = localizedApiError(code, l10n);
          if (localized != null) return localized;
        }
        return data['detail']?.toString() ?? (l10n?.errorGeneric ?? 'An error occurred.');
      }
    } catch (_) {}
    return l10n?.errorGenericRetry ?? 'An error occurred. Please try again.';
  }
  return e?.toString() ?? (l10n?.errorGeneric ?? 'An error occurred.');
}
