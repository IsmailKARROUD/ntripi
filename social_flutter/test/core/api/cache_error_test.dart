// test/core/api/cache_error_test.dart — the cache must not answer a 404.
//
// The regression this pins down: the interceptor was configured with
// `hitCacheOnErrorExcept: []`, which dio_cache_interceptor reads as "fall back
// to the cached body on EVERY error status". So when the server correctly
// answered 404 for a blocked or deleted account, the client silently rendered
// the profile it had cached before the block — for up to maxStale (7 days).
//
// The stack here mirrors createDioClient's ordering deliberately: cache
// interceptor first, then CacheEvictInterceptor, so the eviction only ever sees
// errors the cache layer declined to answer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/cache_evict_interceptor.dart';

const _path = '/users/blocked-account-id';

/// What the backend actually sends for a profile GET: a body, an ETag, and
/// `private, no-cache` from ETagMiddleware — which stores but always
/// revalidates, so every read really does reach the server.
ResponseBody _profile200() => ResponseBody.fromString(
      jsonEncode({'id': 'u-1', 'username': 'aminad'}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'etag': ['"v1"'],
        'cache-control': ['private, no-cache'],
      },
    );

ResponseBody _error(int status) => ResponseBody.fromString(
      jsonEncode({'code': 'user_not_found', 'detail': 'User not found.'}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

/// Returns each queued response once, then repeats the last one.
class _ScriptedAdapter implements HttpClientAdapter {
  final List<ResponseBody Function()> script;
  int calls = 0;

  _ScriptedAdapter(this.script);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final build = script[calls < script.length ? calls : script.length - 1];
    calls++;
    return build();
  }

  @override
  void close({bool force = false}) {}
}

({Dio dio, MemCacheStore store, _ScriptedAdapter adapter}) _makeStack(
  List<ResponseBody Function()> script,
) {
  final store = MemCacheStore();
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    DioCacheInterceptor(
      options: CacheOptions(
        store: store,
        policy: CachePolicy.request,
        hitCacheOnErrorExcept: kNeverServeStaleFor,
        maxStale: const Duration(days: 7),
        priority: CachePriority.normal,
        keyBuilder: CacheOptions.defaultCacheKeyBuilder,
      ),
    ),
  );
  dio.interceptors.add(CacheEvictInterceptor(store));
  final adapter = _ScriptedAdapter(script);
  dio.httpClientAdapter = adapter;
  return (dio: dio, store: store, adapter: adapter);
}

String _keyFor(Dio dio) => CacheOptions.defaultCacheKeyBuilder(
      RequestOptions(path: _path, baseUrl: dio.options.baseUrl),
    );

void main() {
  group('cached GET that later 404s', () {
    test(
        'Given a cached profile, When the server answers 404, '
        'Then the caller gets the 404 and not the cached body', () async {
      final stack = _makeStack([_profile200, () => _error(404)]);

      final first = await stack.dio.get(_path);
      expect(first.statusCode, 200);

      await expectLater(
        stack.dio.get(_path),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          404,
        )),
      );
      expect(stack.adapter.calls, 2, reason: 'the 404 must reach the server');
    });

    test(
        'Given a 404 has been seen, When the entry is checked, '
        'Then it is gone from the store', () async {
      final stack = _makeStack([_profile200, () => _error(404)]);

      await stack.dio.get(_path);
      expect(await stack.store.exists(_keyFor(stack.dio)), isTrue);

      await expectLater(stack.dio.get(_path), throwsA(isA<DioException>()));

      // Left in place, the offline branch — which hits cache unconditionally,
      // whatever hitCacheOnErrorExcept says — would resurrect the profile.
      expect(await stack.store.exists(_keyFor(stack.dio)), isFalse);
    });

    test(
        'Given a cached profile, When the server answers 403, '
        'Then the caller gets the 403 and the entry is evicted', () async {
      final stack = _makeStack([_profile200, () => _error(403)]);

      await stack.dio.get(_path);
      await expectLater(stack.dio.get(_path), throwsA(isA<DioException>()));

      expect(await stack.store.exists(_keyFor(stack.dio)), isFalse);
    });
  });

  group('resilience is preserved', () {
    test(
        'Given a cached profile, When the server answers 500, '
        'Then the cached body is still served', () async {
      final stack = _makeStack([_profile200, () => _error(500)]);

      await stack.dio.get(_path);
      final second = await stack.dio.get(_path);

      // A server fault is not the server saying "you may not see this".
      // A cache hit always reports 304 and carries the stored body.
      expect(second.statusCode, 304);
      expect((second.data as Map)['username'], 'aminad');
      expect(await stack.store.exists(_keyFor(stack.dio)), isTrue);
    });

    test(
        'Given a cached profile, When the device is offline, '
        'Then the cached body is still served', () async {
      final store = MemCacheStore();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        DioCacheInterceptor(
          options: CacheOptions(
            store: store,
            policy: CachePolicy.request,
            hitCacheOnErrorExcept: kNeverServeStaleFor,
            maxStale: const Duration(days: 7),
          ),
        ),
      );
      dio.interceptors.add(CacheEvictInterceptor(store));

      var offline = false;
      dio.httpClientAdapter = _OfflineAfterFirst(() => offline);

      final first = await dio.get(_path);
      expect(first.statusCode, 200);

      offline = true;
      final second = await dio.get(_path);

      // A connection error carries no Response at all, so it takes the
      // interceptor's earlier branch and never consults kNeverServeStaleFor.
      expect(second.statusCode, 304);
      expect((second.data as Map)['username'], 'aminad');
    });
  });
}

class _OfflineAfterFirst implements HttpClientAdapter {
  final bool Function() isOffline;

  _OfflineAfterFirst(this.isOffline);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (isOffline()) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    return _profile200();
  }

  @override
  void close({bool force = false}) {}
}
