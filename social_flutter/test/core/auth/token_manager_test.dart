// test/core/auth/token_manager_test.dart — Unit tests for TokenManager.
//
// Focus areas:
//   1. Refresh deduplication — N concurrent callers must trigger exactly
//      ONE /auth/refresh request, and all receive the same new token.
//   2. Persistence — successful refresh writes both new tokens to storage.
//   3. SessionExpiredException — server-side 4xx clears storage.
//   4. NetworkUnavailableException — transient errors leave storage alone.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/auth/token_manager.dart';

/// Build a JWT-shaped string whose payload contains `exp = <unixSeconds>`.
/// Not signed correctly — that doesn't matter for client-side checks.
String _jwtWithExp(int unixSeconds) {
  String b64(Map<String, dynamic> json) => base64Url
      .encode(utf8.encode(jsonEncode(json)))
      .replaceAll('=', '');
  final header = b64({'alg': 'HS256', 'typ': 'JWT'});
  final payload = b64({'sub': 'u', 'exp': unixSeconds, 'iat': unixSeconds - 60});
  return '$header.$payload.fakesignature';
}

void main() {
  (Dio, DioAdapter) makeBareDio() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final adapter = DioAdapter(dio: dio);
    return (dio, adapter);
  }

  Map<String, dynamic> tokenPair({
    String access = 'new-access',
    String refresh = 'new-refresh',
  }) =>
      {
        'access_token': access,
        'refresh_token': refresh,
        'refresh_expires_at': DateTime.now()
            .add(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
        'token_type': 'bearer',
        'user_id': 'u',
        'username': 'alice',
      };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('getValidAccessToken', () {
    test('returns null when no access token is stored', () async {
      final (dio, _) = makeBareDio();
      final tm = TokenManager(dio);
      expect(await tm.getValidAccessToken(), isNull);
    });

    test('returns the stored token when it is still valid', () async {
      final futureExp =
          DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
              1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(futureExp),
      });

      final (dio, _) = makeBareDio();
      final tm = TokenManager(dio);
      final token = await tm.getValidAccessToken();
      expect(token, isNotNull);
    });

    test('throws SessionExpired when access is expired and no refresh saved',
        () async {
      final pastExp =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(pastExp),
      });

      final (dio, _) = makeBareDio();
      final tm = TokenManager(dio);

      Object? caught;
      try {
        await tm.getValidAccessToken();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<SessionExpiredException>());

      // Storage should have been cleared.
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), isNull);
    });
  });

  group('refresh dedup', () {
    test('10 concurrent callers trigger exactly ONE /auth/refresh request',
        () async {
      final pastExp =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(pastExp),
        'ntripi_refresh_token': 'old-refresh',
      });

      final (dio, adapter) = makeBareDio();

      var requestCount = 0;
      // onPost can only register one response per matching request. We use
      // a single registration and count via a Completer that lets the
      // adapter respond, while the test thread counts.
      adapter.onPost(
        kRefreshEndpoint,
        (server) {
          requestCount++;
          return server.reply(200, tokenPair());
        },
        data: {'refresh_token': 'old-refresh'},
      );

      final tm = TokenManager(dio);

      final results = await Future.wait(
        List.generate(10, (_) => tm.getValidAccessToken()),
      );

      expect(requestCount, 1);
      expect(results.every((t) => t == 'new-access'), isTrue);
    });

    test('persists new token pair after successful refresh', () async {
      final pastExp =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(pastExp),
        'ntripi_refresh_token': 'old-refresh',
      });

      final (dio, adapter) = makeBareDio();
      adapter.onPost(
        kRefreshEndpoint,
        (server) => server.reply(200, tokenPair()),
        data: {'refresh_token': 'old-refresh'},
      );

      final tm = TokenManager(dio);
      await tm.getValidAccessToken();

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), 'new-access');
      expect(await storage.read(key: 'ntripi_refresh_token'), 'new-refresh');
    });
  });

  group('refresh error handling', () {
    test('401 invalid_grant clears tokens and throws SessionExpired',
        () async {
      final pastExp =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(pastExp),
        'ntripi_refresh_token': 'revoked-refresh',
      });

      final (dio, adapter) = makeBareDio();
      adapter.onPost(
        kRefreshEndpoint,
        (server) => server.reply(401, {'detail': 'invalid_grant'}),
        data: {'refresh_token': 'revoked-refresh'},
      );

      final tm = TokenManager(dio);

      Object? caught;
      try {
        await tm.getValidAccessToken();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<SessionExpiredException>());

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_access_token'), isNull);
      expect(await storage.read(key: 'ntripi_refresh_token'), isNull);
    });

    test('connection error throws NetworkUnavailable and preserves tokens',
        () async {
      final pastExp =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
              1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(pastExp),
        'ntripi_refresh_token': 'alive-refresh',
      });

      final (dio, adapter) = makeBareDio();
      adapter.onPost(
        kRefreshEndpoint,
        (server) => server.throws(
          0,
          DioException(
            requestOptions: RequestOptions(path: kRefreshEndpoint),
            type: DioExceptionType.connectionError,
            error: 'offline',
          ),
        ),
        data: {'refresh_token': 'alive-refresh'},
      );

      final tm = TokenManager(dio);

      Object? caught;
      try {
        await tm.getValidAccessToken();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<NetworkUnavailableException>());

      const storage = FlutterSecureStorage();
      expect(
        await storage.read(key: 'ntripi_refresh_token'),
        'alive-refresh',
      );
    });
  });
}
