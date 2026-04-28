// test/repositories/auth_repository_test.dart — Unit tests for AuthRepository.
//
// These tests verify that AuthRepository sends the right HTTP requests and
// correctly parses the API responses. No real network is used — Dio calls
// are intercepted by DioAdapter (http_mock_adapter).
//
// flutter_secure_storage is stubbed via setMockInitialValues so we can
// verify that tokens are saved/deleted without touching real Keychain storage.

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Test setup helpers
  // ---------------------------------------------------------------------------

  /// Creates a fresh Dio instance + DioAdapter pair for each test.
  /// Using a fresh instance avoids state leaking between tests.
  (Dio, DioAdapter) _makeDio() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final adapter = DioAdapter(dio: dio);
    return (dio, adapter);
  }

  /// A valid API response body from POST /auth/register or POST /auth/login.
  const _authResponseBody = {
    'access_token': 'test-jwt-token',
    'user_id': 'user-uuid-123',
    'username': 'alice1',
  };

  // ---------------------------------------------------------------------------
  // Shared setUp: reset secure storage mock before every test so tokens from
  // one test don't bleed into the next.
  // ---------------------------------------------------------------------------
  setUp(() {
    // Provide an empty in-memory store that replaces real Keychain/Keystore.
    FlutterSecureStorage.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // register()
  // ---------------------------------------------------------------------------

  group('AuthRepository.register', () {
    test('sends correct POST body and returns AuthResult on 200', () async {
      final (dio, adapter) = _makeDio();

      // Stub POST /auth/register → 201 Created with token payload.
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(201, _authResponseBody),
        data: {
          'username': 'alice1',
          'email': 'alice@test.com',
          'password': 'secret123',
          'display_name': 'Alice',
          'tos_accepted': true,
        },
      );

      final repo = AuthRepository(dio);
      final result = await repo.register(
        username: 'alice1',
        email: 'alice@test.com',
        password: 'secret123',
        displayName: 'Alice',
        tosAccepted: true,
      );

      // Verify that the response fields are correctly parsed.
      expect(result.accessToken, 'test-jwt-token');
      expect(result.userId, 'user-uuid-123');
      expect(result.username, 'alice1');
    });

    test('omits display_name from request body when null or empty', () async {
      final (dio, adapter) = _makeDio();

      // The stub matches a body WITHOUT display_name — if the repo accidentally
      // sends it, the adapter won't match and the call will throw DioException,
      // causing the test to fail.
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(201, _authResponseBody),
        data: {
          'username': 'bob1',
          'email': 'bob@test.com',
          'password': 'secret456',
          'tos_accepted': true,
        },
      );

      final repo = AuthRepository(dio);
      // displayName not provided → should be omitted from body.
      final result = await repo.register(
        username: 'bob1',
        email: 'bob@test.com',
        password: 'secret456',
        tosAccepted: true,
      );

      // If we get here, the body matched — display_name was correctly omitted.
      expect(result.userId, 'user-uuid-123');
    });

    test('saves token to secure storage after successful register', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(201, _authResponseBody),
        data: {
          'username': 'alice1',
          'email': 'alice@test.com',
          'password': 'secret123',
          'tos_accepted': true,
        },
      );

      final repo = AuthRepository(dio);
      await repo.register(
        username: 'alice1',
        email: 'alice@test.com',
        password: 'secret123',
        tosAccepted: true,
      );

      // Read the stored token directly from the mock secure storage.
      const storage = FlutterSecureStorage();
      final stored = await storage.read(key: 'ntripi_access_token');
      expect(stored, 'test-jwt-token');
    });

    test('throws DioException on 400 (e.g. username already taken)', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(400, {'detail': 'Username already taken'}),
        data: {
          'username': 'alice1',
          'email': 'alice@test.com',
          'password': 'secret123',
          'tos_accepted': true,
        },
      );

      final repo = AuthRepository(dio);
      expect(
        () => repo.register(
          username: 'alice1',
          email: 'alice@test.com',
          password: 'secret123',
          tosAccepted: true,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // login()
  // ---------------------------------------------------------------------------

  group('AuthRepository.login', () {
    test('sends correct POST body and returns AuthResult on 200', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(200, _authResponseBody),
        data: {'email': 'alice@test.com', 'password': 'secret123'},
      );

      final repo = AuthRepository(dio);
      final result = await repo.login(
        identifier: 'alice@test.com',
        password: 'secret123',
      );

      expect(result.accessToken, 'test-jwt-token');
      expect(result.userId, 'user-uuid-123');
      expect(result.username, 'alice1');
    });

    test('saves token to secure storage after successful login', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(200, _authResponseBody),
        data: {'email': 'alice@test.com', 'password': 'secret123'},
      );

      final repo = AuthRepository(dio);
      await repo.login(identifier: 'alice@test.com', password: 'secret123');

      const storage = FlutterSecureStorage();
      final stored = await storage.read(key: 'ntripi_access_token');
      expect(stored, 'test-jwt-token');
    });

    test('throws DioException on 401 (wrong credentials)', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(401, {'detail': 'Invalid credentials'}),
        data: {'email': 'alice@test.com', 'password': 'wrong'},
      );

      final repo = AuthRepository(dio);
      expect(
        () => repo.login(identifier: 'alice@test.com', password: 'wrong'),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // logout()
  // ---------------------------------------------------------------------------

  group('AuthRepository.logout', () {
    test('clears token from secure storage', () async {
      // Pre-populate the mock storage with a token (simulates a logged-in user).
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': 'existing-jwt-token',
      });

      final (dio, _) = _makeDio();
      final repo = AuthRepository(dio);
      await repo.logout();

      // Token must be gone after logout.
      const storage = FlutterSecureStorage();
      final stored = await storage.read(key: 'ntripi_access_token');
      expect(stored, isNull);
    });

    test('is idempotent — logout when already logged out does not throw',
        () async {
      // Storage is already empty (set in setUp).
      final (dio, _) = _makeDio();
      final repo = AuthRepository(dio);

      // Should complete without throwing.
      await expectLater(repo.logout(), completes);
    });
  });
}
