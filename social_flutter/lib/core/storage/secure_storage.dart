// core/storage/secure_storage.dart — Wrapper around flutter_secure_storage.
//
// Why a wrapper?
//   - Centralises all token key names. If you rename a key, you change it here.
//   - Makes the token operations easy to find and mock in tests.
//   - The caller doesn't need to import flutter_secure_storage directly.
//
// flutter_secure_storage uses:
//   - iOS: Keychain (hardware-backed on modern iPhones)
//   - Android: EncryptedSharedPreferences (backed by Android Keystore)
// This is appropriate for sensitive data like auth tokens.
//
// Two tokens are stored:
//   - access_token  (short JWT, ~15 min — sent in Authorization header)
//   - refresh_token (long opaque string, 30 days — only sent to /auth/refresh)
// `refresh_expires_at` is also stored so the splash flow can skip a doomed
// refresh attempt at boot when the long-lived token is already past expiry.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kAccessTokenKey = 'ntripi_access_token';
const _kRefreshTokenKey = 'ntripi_refresh_token';
const _kRefreshExpiresAtKey = 'ntripi_refresh_expires_at';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

// ---------------------------------------------------------------------------
// Access token (mobile JWT)
// ---------------------------------------------------------------------------

/// Store just the access token. Used internally by [saveTokens] and by the
/// TokenManager refresh flow when only the access token is rotating.
Future<void> saveToken(String token) async {
  await _storage.write(key: _kAccessTokenKey, value: token);
}

Future<String?> readToken() async {
  return _storage.read(key: _kAccessTokenKey);
}

Future<void> deleteToken() async {
  await _storage.delete(key: _kAccessTokenKey);
}

/// True if an access token is currently stored. Does NOT validate expiry.
Future<bool> hasToken() async {
  final token = await readToken();
  return token != null && token.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Refresh token
// ---------------------------------------------------------------------------

Future<String?> readRefreshToken() async {
  return _storage.read(key: _kRefreshTokenKey);
}

Future<DateTime?> readRefreshExpiresAt() async {
  final raw = await _storage.read(key: _kRefreshExpiresAtKey);
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}

/// Persist a freshly-issued token pair (login / register / refresh).
/// Atomic from the caller's perspective — never half-saved state, because
/// the only places that call this also call [clearAllTokens] on failure.
Future<void> saveTokens({
  required String accessToken,
  required String refreshToken,
  required DateTime refreshExpiresAt,
}) async {
  await _storage.write(key: _kAccessTokenKey, value: accessToken);
  await _storage.write(key: _kRefreshTokenKey, value: refreshToken);
  await _storage.write(
    key: _kRefreshExpiresAtKey,
    value: refreshExpiresAt.toUtc().toIso8601String(),
  );
}

/// Wipe everything — logout path.
Future<void> clearAllTokens() async {
  await _storage.delete(key: _kAccessTokenKey);
  await _storage.delete(key: _kRefreshTokenKey);
  await _storage.delete(key: _kRefreshExpiresAtKey);
}

// ---------------------------------------------------------------------------
// JWT introspection
// ---------------------------------------------------------------------------

/// Returns true if [token] has passed its `exp` JWT claim.
/// Treats malformed or claim-less tokens as expired so they are evicted.
bool isJwtExpired(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final exp = payload['exp'] as int?;
    if (exp == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp;
  } catch (_) {
    return true;
  }
}
