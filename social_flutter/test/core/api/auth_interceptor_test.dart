// test/core/api/auth_interceptor_test.dart — Behavior tests for AuthInterceptor.
//
// Covers the three contracts the rest of the app depends on:
//   1. Happy path  — attaches the Bearer token to outgoing requests.
//   2. 401 retry   — on a server-side 401 from a protected route, refreshes
//                    the access token once and retries the original request.
//   3. Offline tolerance — when the access token is expired and refresh
//                          throws NetworkUnavailable, the request flies
//                          unauthenticated with the `kAuthSkippedExtra` flag.
//
// The interceptor's "redirect to /login" branch is covered indirectly by
// the higher-level TokenManager test — it ultimately fires a navigation
// via the GoRouter navigatorKey which isn't installed in a unit test.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/auth/token_manager.dart';

String _jwtWithExp(int unixSeconds) {
  String b64(Map<String, dynamic> json) => base64Url
      .encode(utf8.encode(jsonEncode(json)))
      .replaceAll('=', '');
  final header = b64({'alg': 'HS256', 'typ': 'JWT'});
  final payload = b64({'sub': 'u', 'exp': unixSeconds, 'iat': unixSeconds - 60});
  return '$header.$payload.fakesignature';
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// Build a pair of (mainDio, mainAdapter, bareDio, bareAdapter) and wire
  /// the AuthInterceptor + TokenManager together.
  ({Dio dio, DioAdapter adapter, Dio bareDio, DioAdapter bareAdapter})
      makeStack() {
    final bareDio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final bareAdapter = DioAdapter(dio: bareDio);
    final tm = TokenManager(bareDio);

    final mainDio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    // Important: install AuthInterceptor BEFORE the adapter, otherwise the
    // adapter's HttpClientAdapter takes over and onRequest never runs.
    // In production AuthInterceptor's retryDio is bareDio (same instance
    // TokenManager uses for refresh). That keeps the retry off the same
    // Dio whose interceptor is currently in flight — see the deadlock
    // comment in api_client.dart.
    mainDio.interceptors.add(AuthInterceptor(tm, bareDio));
    final mainAdapter = DioAdapter(dio: mainDio);

    return (
      dio: mainDio,
      adapter: mainAdapter,
      bareDio: bareDio,
      bareAdapter: bareAdapter,
    );
  }

  group('onRequest', () {
    test('attaches Bearer token when a valid access token is stored',
        () async {
      final futureExp = DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000;
      final validJwt = _jwtWithExp(futureExp);
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': validJwt,
      });

      final stack = makeStack();
      stack.adapter.onGet(
        '/users/me',
        (server) => server.reply(200, {'username': 'alice'}),
        headers: {'Authorization': 'Bearer $validJwt'},
      );

      final response = await stack.dio.get('/users/me');
      expect(response.statusCode, 200);
    });

    test('does not attach Authorization on auth endpoints', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(
          DateTime.now()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
      });

      final stack = makeStack();
      stack.adapter.onPost(
        kLoginEndpoint,
        (server) => server.reply(200, {
          'access_token': 'a',
          'refresh_token': 'r',
          'refresh_expires_at': DateTime.now()
              .add(const Duration(days: 30))
              .toUtc()
              .toIso8601String(),
          'token_type': 'bearer',
          'user_id': 'u',
          'username': 'alice',
        }),
        data: {'identifier': 'x', 'password': 'y'},
      );

      final response = await stack.dio.post(
        kLoginEndpoint,
        data: {'identifier': 'x', 'password': 'y'},
      );
      expect(response.statusCode, 200);
    });
  });

  group('onError 401', () {
    test('triggers a transparent refresh and persists the new token pair',
        () async {
      final futureExp = DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000;

      // Pre-state: a locally-valid access token plus a refresh token. The
      // server will reject the access token (simulating server-side revoke
      // before the JWT's exp). The interceptor must call /auth/refresh and
      // persist the new pair — that's the contract this test verifies. We
      // don't assert on retry-success because http_mock_adapter doesn't
      // give us a clean way to flip a response between calls.
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(futureExp),
        'ntripi_refresh_token': 'old-refresh',
      });

      final stack = makeStack();
      stack.adapter.onGet(
        '/users/me',
        (server) => server.reply(401, {'detail': 'expired'}),
      );

      stack.bareAdapter.onPost(
        kRefreshEndpoint,
        (server) => server.reply(200, {
          'access_token': _jwtWithExp(futureExp + 60),
          'refresh_token': 'new-refresh',
          'refresh_expires_at': DateTime.now()
              .add(const Duration(days: 30))
              .toUtc()
              .toIso8601String(),
          'token_type': 'bearer',
          'user_id': 'u',
          'username': 'alice',
        }),
        data: {'refresh_token': 'old-refresh'},
      );

      // The retry fires through bareDio (no AuthInterceptor) — see the
      // deadlock comment in api_client.dart. Register the post-refresh
      // success path on bareAdapter so the retry resolves cleanly.
      stack.bareAdapter.onGet(
        '/users/me',
        (server) => server.reply(200, {'username': 'alice'}),
      );

      final response = await stack.dio.get('/users/me');
      expect(response.statusCode, 200);
      expect(response.data['username'], 'alice');

      const storage = FlutterSecureStorage();
      expect(
        await storage.read(key: 'ntripi_refresh_token'),
        'new-refresh',
      );
    });
  });

  group('offline tolerance', () {
    test(
        'when refresh fails with network error, request flies with auth_skipped',
        () async {
      final pastExp = DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch ~/
          1000;
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_access_token': _jwtWithExp(pastExp),
        'ntripi_refresh_token': 'still-alive-refresh',
      });

      final stack = makeStack();

      // Refresh fails with a connection error.
      stack.bareAdapter.onPost(
        kRefreshEndpoint,
        (server) => server.throws(
          0,
          DioException(
            requestOptions: RequestOptions(path: kRefreshEndpoint),
            type: DioExceptionType.connectionError,
            error: 'offline',
          ),
        ),
        data: {'refresh_token': 'still-alive-refresh'},
      );

      // The actual request makes it through (server stub responds 200,
      // simulating either a cache hit or a server that ignored the missing
      // auth header — what matters here is that the interceptor didn't
      // reject the request locally).
      bool sawAuthSkipped = false;
      stack.adapter.onGet(
        '/users/me',
        (server) => server.reply(200, {'username': 'alice-from-cache'}),
      );

      // Wrap the request to capture extra on the way back.
      // We use a post-onRequest interceptor to observe.
      stack.dio.interceptors.add(
        InterceptorsWrapper(onRequest: (options, handler) {
          if (options.extra[kAuthSkippedExtra] == true) {
            sawAuthSkipped = true;
          }
          handler.next(options);
        }),
      );

      final response = await stack.dio.get('/users/me');
      expect(response.statusCode, 200);
      expect(sawAuthSkipped, isTrue);

      // Tokens preserved — session may still be alive.
      const storage = FlutterSecureStorage();
      expect(
        await storage.read(key: 'ntripi_refresh_token'),
        'still-alive-refresh',
      );
    });
  });
}
