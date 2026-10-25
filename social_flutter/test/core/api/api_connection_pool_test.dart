// test/core/api/api_connection_pool_test.dart — the API's connections stay
// open between requests, and start over when one kept may have died.
//
// Dio's own adapter closed an unused connection after 3 s, so nearly every
// request paid a new TCP and TLS handshake. These run real requests against a
// loopback server that answers with the client's port: the same port is the
// same connection. Plain test() only — the widget binding swaps HttpClient
// for a mock that answers 400 to everything.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_connection_pool.dart';
import 'package:ntripi/core/auth/token_manager.dart';

void main() {
  late HttpServer server;

  // A request to /held tells [held] it arrived, then waits for [release].
  late Completer<void> held;
  late Completer<void> release;

  setUp(() async {
    held = Completer<void>();
    release = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/held') {
        held.complete();
        await release.future;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"port": ${request.connectionInfo!.remotePort}}');
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Dio client(ApiConnectionPool pool) => Dio(
        BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'),
      )..httpClientAdapter = pool;

  Future<int> portOf(Dio dio, [String path = '/']) async =>
      (await dio.get<Map<String, dynamic>>(path)).data!['port'] as int;

  Future<void> serverConnectionsDropTo(int count) async {
    for (var i = 0; i < 200 && server.connectionsInfo().total != count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(server.connectionsInfo().total, count);
  }

  test('an unused connection stays open two minutes, under Cloudflare\'s 400 s',
      () {
    expect(kApiConnectionIdleTimeout, const Duration(seconds: 120));
    expect(kApiConnectionIdleTimeout, lessThan(const Duration(seconds: 400)),
        reason: 'At 400 s Cloudflare and the app close an idle connection at '
            'the same moment, and a request sent then fails.');
    expect(ApiConnectionPool().idleTimeout, kApiConnectionIdleTimeout);
  });

  test('requests one after another share a connection', () async {
    final dio = client(ApiConnectionPool());
    final first = await portOf(dio);
    expect(await portOf(dio), first);
  });

  test('dio and bareDio share one pool', () {
    bareDio = createBareDio();
    final api = createDioClient(tokenManager: TokenManager(bareDio));
    expect(bareDio.httpClientAdapter, same(apiConnectionPool));
    expect(api.httpClientAdapter, same(apiConnectionPool),
        reason: 'One pool, so the token refresh bareDio sends before a request '
            'opens the connection that request then reuses.');
  });

  test('after retire the next request opens a new connection, and the idle one '
      'closes', () async {
    final pool = ApiConnectionPool();
    final dio = client(pool);
    final before = await portOf(dio);

    pool.retire();

    expect(await portOf(dio), isNot(before));
    await serverConnectionsDropTo(1);
  });

  test('a request under way when the pool retires still gets its answer, then '
      'its connection closes', () async {
    final pool = ApiConnectionPool();
    final answer = portOf(client(pool), '/held');
    await held.future;

    pool.retire();
    release.complete();

    expect(await answer, isA<int>());
    await serverConnectionsDropTo(0);
  });

  test('retire leaves a request that is still connecting alone', () async {
    // Accepts the TCP connection and never answers the TLS handshake, so the
    // request stays in the phase HttpClient.close() would cancel.
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<Socket>();
    silent.listen(accepted.complete);
    final pool = ApiConnectionPool();

    var ended = false;
    unawaited(pool
        .fetch(
          RequestOptions(
            baseUrl: 'https://127.0.0.1:${silent.port}',
            path: '/',
          ),
          null,
          null,
        )
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => ended = true));
    final socket = await accepted.future;

    pool.retire();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ended, isFalse,
        reason: 'Retiring must not end an attempt that is still connecting: '
            'a save tapped just before leaving the app would fail.');
    socket.destroy();
    await silent.close();
  });

  test('leaving the screen retires the pool; the app switcher does not',
      () async {
    final pool = ApiConnectionPool();
    final dio = client(pool);
    final first = await portOf(dio);

    pool.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(await portOf(dio), first);

    pool.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(await portOf(dio), isNot(first));
  });

  test('only api_client.dart builds a Dio for the API', () {
    final builders = {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (RegExp(r'baseUrl:\s*kApiBaseUrl').hasMatch(
            file.readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '')))
          file.path,
    };
    expect(builders, {'lib/core/api/api_client.dart'},
        reason: 'A Dio built anywhere else bypasses apiConnectionPool: it '
            'opens a new connection after every 3 s pause, and keeps a dead '
            'one across a sleep or a network change.');
  });
}
