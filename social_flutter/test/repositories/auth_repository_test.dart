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
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/auth/data/auth_repository.dart';

void main() {
  /// Creates a (main dio, bare dio, adapter-for-main, adapter-for-bare) tuple.
  /// AuthRepository takes two Dio instances — main for login/register and
  /// bare for /auth/logout (no AuthInterceptor recursion).
  (Dio, Dio, DioAdapter, DioAdapter) _makeDios() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final bareDio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final adapter = DioAdapter(dio: dio);
    final bareAdapter = DioAdapter(dio: bareDio);
    return (dio, bareDio, adapter, bareAdapter);
  }

  /// A valid TokenPair response body from /auth/register, /auth/login,
  /// or /auth/refresh.
  final _authResponseBody = {
    'access_token': 'test-jwt-token',
    'refresh_token': 'test-refresh-token',
    'refresh_expires_at': '2026-07-12T12:00:00.000Z',
    'token_type': 'bearer',
    'user_id': 'user-uuid-123',
    'username': 'alice1',
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // register()
  // ---------------------------------------------------------------------------

  group('AuthRepository.register', () {
    test('sends correct POST body and returns AuthResult on 201', () async {
      final (dio, bareDio, adapter, _) = _makeDios();

      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(201, _authResponseBody),
        data: {
          'username': 'alice1',
          'email': 'alice@test.com',
          'password': 'secret123',
          'display_name': 'Alice',
          'tos_accepted': true,
          'date_of_birth': '2000-01-01',
        },
      );

      final repo = AuthRepository(dio, bareDio);
      final result = await repo.register(
        username: 'alice1',
        email: 'alice@test.com',
        password: 'secret123',
        displayName: 'Alice',
        tosAccepted: true,
        dateOfBirth: DateTime(2000, 1, 1),
      );

      expect(result.accessToken, 'test-jwt-token');
      expect(result.refreshToken, 'test-refresh-token');
      expect(result.userId, 'user-uuid-123');
      expect(result.username, 'alice1');
    });

    test('omits display_name from request body when null or empty', () async {
      final (dio, bareDio, adapter, _) = _makeDios();

      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(201, _authResponseBody),
        data: {
          'username': 'bob1',
          'email': 'bob@test.com',
          'password': 'secret456',
          'tos_accepted': true,
          'date_of_birth': '2000-01-01',
        },
      );

      final repo = AuthRepository(dio, bareDio);
      final result = await repo.register(
        username: 'bob1',
        email: 'bob@test.com',
        password: 'secret456',
        tosAccepted: true,
        dateOfBirth: DateTime(2000, 1, 1),
      );

      expect(result.userId, 'user-uuid-123');
    });

    test('saves both tokens to secure storage after successful register',
        () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(201, _authResponseBody),
        data: {
          'username': 'alice1',
          'email': 'alice@test.com',
          'password': 'secret123',
          'tos_accepted': true,
          'date_of_birth': '2000-01-01',
        },
      );

      final repo = AuthRepository(dio, bareDio);
      await repo.register(
        username: 'alice1',
        email: 'alice@test.com',
        password: 'secret123',
        tosAccepted: true,
        dateOfBirth: DateTime(2000, 1, 1),
      );

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), 'test-jwt-token');
      expect(
        await storage.read(key: 'ntripi_refresh_token'),
        'test-refresh-token',
      );
      expect(
        await storage.read(key: 'ntripi_refresh_expires_at'),
        isNotNull,
      );
    });

    test('throws DioException on 400 (e.g. username already taken)', () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(400, {'detail': 'Username already taken'}),
        data: {
          'username': 'alice1',
          'email': 'alice@test.com',
          'password': 'secret123',
          'tos_accepted': true,
          'date_of_birth': '2000-01-01',
        },
      );

      final repo = AuthRepository(dio, bareDio);
      expect(
        () => repo.register(
          username: 'alice1',
          email: 'alice@test.com',
          password: 'secret123',
          tosAccepted: true,
          dateOfBirth: DateTime(2000, 1, 1),
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // A blocked sign-up address: the refusal reaches the screen, no session stays
  // ---------------------------------------------------------------------------

  group('AuthRepository, an address that may not sign up', () {
    const refusal = {
      'detail': "This email address can't be used to create an account.",
      'code': 'email_unavailable',
    };
    final isTheRefusal = isA<DioException>().having(
      apiErrorCode, 'code', 'email_unavailable',
    );

    Future<void> expectNoSession() async {
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), isNull);
      expect(await storage.read(key: 'ntripi_refresh_token'), isNull);
      expect(await storage.read(key: 'ntripi_refresh_expires_at'), isNull);
    }

    test(
        'Given the blocked address, When register is called, '
        'Then the code reaches the caller and no session is saved', () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kRegisterEndpoint,
        (server) => server.reply(400, refusal),
        data: Matchers.any,
      );

      await expectLater(
        AuthRepository(dio, bareDio).register(
          username: 'alice1',
          email: 'blocked@test.com',
          password: 'secret123',
          tosAccepted: true,
          dateOfBirth: DateTime(2000, 1, 1),
        ),
        throwsA(isTheRefusal),
      );
      await expectNoSession();
    });

    test(
        'Given the blocked address, When loginWithGoogle is called, '
        'Then the code reaches the caller and no session is saved', () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kGoogleAuthEndpoint,
        (server) => server.reply(400, refusal),
        data: Matchers.any,
      );

      await expectLater(
        AuthRepository(dio, bareDio).loginWithGoogle(idToken: 'id-token'),
        throwsA(isTheRefusal),
      );
      await expectNoSession();
    });
  });

  // ---------------------------------------------------------------------------
  // login()
  // ---------------------------------------------------------------------------

  group('AuthRepository.login', () {
    test('sends correct POST body and returns AuthResult on 200', () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(200, _authResponseBody),
        data: {'identifier': 'alice@test.com', 'password': 'secret123'},
      );

      final repo = AuthRepository(dio, bareDio);
      final result = await repo.login(
        identifier: 'alice@test.com',
        password: 'secret123',
      );

      expect(result.accessToken, 'test-jwt-token');
      expect(result.refreshToken, 'test-refresh-token');
      expect(result.userId, 'user-uuid-123');
      expect(result.username, 'alice1');
    });

    test('saves both tokens to secure storage after successful login',
        () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(200, _authResponseBody),
        data: {'identifier': 'alice@test.com', 'password': 'secret123'},
      );

      final repo = AuthRepository(dio, bareDio);
      await repo.login(identifier: 'alice@test.com', password: 'secret123');

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), 'test-jwt-token');
      expect(
        await storage.read(key: 'ntripi_refresh_token'),
        'test-refresh-token',
      );
    });

    test('throws DioException on 401 (wrong credentials)', () async {
      final (dio, bareDio, adapter, _) = _makeDios();
      adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(401, {'detail': 'Invalid credentials'}),
        data: {'identifier': 'alice@test.com', 'password': 'wrong'},
      );

      final repo = AuthRepository(dio, bareDio);
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
    test('calls /auth/logout with refresh token, then clears storage',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': 'existing-jwt-token',
        'ntripi_refresh_token': 'existing-refresh-token',
        'ntripi_refresh_expires_at': '2026-07-12T12:00:00.000Z',
      });

      final (dio, bareDio, _, bareAdapter) = _makeDios();
      bareAdapter.onPost(
        kLogoutEndpoint,
        (server) => server.reply(204, null),
        data: {'refresh_token': 'existing-refresh-token'},
      );

      final repo = AuthRepository(dio, bareDio);
      await repo.logout();

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), isNull);
      expect(await storage.read(key: 'ntripi_refresh_token'), isNull);
      expect(await storage.read(key: 'ntripi_refresh_expires_at'), isNull);
    });

    test('still clears storage when server-side logout fails', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': 'existing-jwt-token',
        'ntripi_refresh_token': 'existing-refresh-token',
      });

      final (dio, bareDio, _, bareAdapter) = _makeDios();
      // Server is down — logout must still wipe local tokens.
      bareAdapter.onPost(
        kLogoutEndpoint,
        (server) => server.reply(500, {'detail': 'Server error'}),
        data: {'refresh_token': 'existing-refresh-token'},
      );

      final repo = AuthRepository(dio, bareDio);
      await repo.logout();

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), isNull);
      expect(await storage.read(key: 'ntripi_refresh_token'), isNull);
    });

    test('is idempotent — logout when already logged out does not throw',
        () async {
      final (dio, bareDio, _, _) = _makeDios();
      final repo = AuthRepository(dio, bareDio);
      await expectLater(repo.logout(), completes);
    });
  });
}
