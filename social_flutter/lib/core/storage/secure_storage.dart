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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key under which the JWT access token is stored.
const _kTokenKey = 'ntripi_access_token';

/// Singleton storage instance.
/// FlutterSecureStorage is safe to use as a singleton.
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Store the JWT access token securely.
Future<void> saveToken(String token) async {
  await _storage.write(key: _kTokenKey, value: token);
}

/// Read the stored JWT access token. Returns null if not set.
Future<String?> readToken() async {
  return _storage.read(key: _kTokenKey);
}

/// Delete the stored JWT token (on logout or when a 401 is received).
Future<void> deleteToken() async {
  await _storage.delete(key: _kTokenKey);
}

/// True if a token is currently stored (user appears to be logged in).
/// NOTE: This does NOT validate the token — it may be expired.
/// The interceptor handles 401 responses by clearing the token.
Future<bool> hasToken() async {
  final token = await readToken();
  return token != null && token.isNotEmpty;
}
