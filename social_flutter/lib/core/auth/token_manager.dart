// core/auth/token_manager.dart — Owns the lifecycle of the access token.
//
// Single responsibility: "give me a valid access token, or tell me why you
// can't." Everything else in the auth flow goes through this.
//
// Why this exists as a separate layer:
//   - AuthInterceptor would otherwise have to know about refresh logic
//     AND in-flight deduplication AND offline detection. That's three
//     responsibilities for one class. We split them.
//   - The refresh deduplication is subtle (see `_refresh` below) and easy
//     to break. Keeping it in one place means there's one set of tests
//     to maintain and one place to look when it misbehaves.
//   - Tests can substitute a fake TokenManager into AuthInterceptor
//     without touching Dio internals.
//
// Concurrency: 10 simultaneous protected requests with an expired access
// token must result in exactly ONE /auth/refresh call, not 10. That's
// what `_inflight` guarantees — see the `_refresh` method.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';

/// Thrown when the server rejected our refresh token (revoked / unknown /
/// expired). The session is dead — the caller should navigate to /login.
class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'SessionExpiredException';
}

/// Thrown when a refresh couldn't be attempted because the network was
/// unreachable. The session is still potentially alive — the caller should
/// fall back to cached content and try again when connectivity returns.
class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException();
  @override
  String toString() => 'NetworkUnavailableException';
}

class TokenManager {
  /// `bareDio` must NOT have the AuthInterceptor installed — otherwise a
  /// refresh would recurse into a refresh.
  TokenManager(this._bareDio);

  final Dio _bareDio;

  /// In-flight refresh future, shared across concurrent callers. We hold
  /// this so 10 parallel requests with the same expired token only fire
  /// ONE /auth/refresh.
  Future<String>? _inflight;

  /// Returns a valid access token, refreshing if needed.
  ///
  ///   - Returns null  → no token at all (user never logged in / logged out)
  ///   - Returns String → valid access token, ready to attach as Bearer
  ///   - Throws SessionExpiredException → refresh attempted, server rejected
  ///   - Throws NetworkUnavailableException → refresh attempted, network down
  Future<String?> getValidAccessToken() async {
    final access = await readToken();
    if (access == null) return null;
    if (!isJwtExpired(access)) return access;

    final refresh = await readRefreshToken();
    if (refresh == null) {
      // Access token is expired AND we have no refresh token — old-format
      // session from before the refresh-token migration. Treat as expired.
      await clearAllTokens();
      throw const SessionExpiredException();
    }
    return _refresh();
  }

  /// Force a refresh even if the current access token still looks valid.
  /// Used by the AuthInterceptor when the server returned 401 (token
  /// revoked server-side before its `exp`).
  Future<String> forceRefresh() => _refresh();

  Future<String> _refresh() {
    // Dart's `??=` evaluates the right-hand side EAGERLY — so writing
    // `_inflight ??= _doRefresh()` would start a refresh even when one
    // is already in flight. Explicit check, then explicit assignment.
    final existing = _inflight;
    if (existing != null) return existing;

    // Wrap _doRefresh in an async closure so the try/finally guarantees
    // we clear _inflight on both success and error — and crucially, the
    // future we return is the SAME future we store in _inflight (no extra
    // whenComplete chain that would create an unhandled-error future when
    // the refresh fails).
    late Future<String> fut;
    fut = () async {
      try {
        return await _doRefresh();
      } finally {
        // `identical` guard: if a late completion fires after a successor
        // refresh has already been registered, don't null out the successor.
        if (identical(_inflight, fut)) _inflight = null;
      }
    }();
    _inflight = fut;
    return fut;
  }

  Future<String> _doRefresh() async {
    final refreshToken = await readRefreshToken();
    if (refreshToken == null) {
      await clearAllTokens();
      throw const SessionExpiredException();
    }

    final Response<dynamic> response;
    try {
      response = await _bareDio.post(
        kRefreshEndpoint,
        data: {'refresh_token': refreshToken},
      );
    } on DioException catch (e) {
      // 4xx from /auth/refresh means the server rejected the token —
      // session is dead, surface that distinctly from a network failure.
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        await clearAllTokens();
        throw const SessionExpiredException();
      }
      // Anything else (timeout, no connection, 5xx) is a transient
      // network problem. Keep the tokens — we'll retry on reconnect.
      throw const NetworkUnavailableException();
    }

    final data = response.data as Map<String, dynamic>;
    final newAccess = data['access_token'] as String;
    final newRefresh = data['refresh_token'] as String;
    final newRefreshExp = DateTime.parse(data['refresh_expires_at'] as String);

    await saveTokens(
      accessToken: newAccess,
      refreshToken: newRefresh,
      refreshExpiresAt: newRefreshExp,
    );
    return newAccess;
  }
}

/// Singleton — instantiated once in main() and read by AuthInterceptor and
/// AuthRepository. Don't put this under AsyncNotifier or it would reset
/// `_inflight` on rebuild and break concurrent-refresh dedup.
///
/// The provider is initialized in main.dart via `overrideWithValue` because
/// it needs a Dio instance that doesn't have AuthInterceptor (chicken and
/// egg). Reading this provider before initialization throws.
final tokenManagerProvider = Provider<TokenManager>((ref) {
  throw UnimplementedError(
    'tokenManagerProvider must be overridden in main.dart',
  );
});
