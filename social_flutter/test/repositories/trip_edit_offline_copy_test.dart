// test/repositories/trip_edit_offline_copy_test.dart — a save keeps the trip's
// offline copy current.
//
// Nothing downloads the trip after a save any more, and that download is what
// used to refresh the HTTP cache's entry for GET /itineraries/{id} — the copy a
// trip shows when the app starts with no connection. The trip a save answers
// with is written there instead, under the signed-in account's own key.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/api/cache_key.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';

const _itinId = 'itin-1';

Map<String, dynamic> _trip(String title) => {
      'id': _itinId,
      'user_id': 'user-1',
      'title': title,
      'cover_image_url': null,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-21T09:00:00.000000Z',
      'updated_at': '2026-10-21T10:00:05.000000Z',
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': 0,
      'description': null,
      'tracks': <Map<String, dynamic>>[],
      'segments': <Map<String, dynamic>>[],
      'annotations': <Map<String, dynamic>>[],
      'can_edit': true,
    };

/// A phone with no connection: every request fails before any response exists,
/// which is what sends the cache layer to its stored copy.
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      throw DioException.connectionError(
          requestOptions: options, reason: 'offline');

  @override
  void close({bool force = false}) {}
}

void main() {
  late MemCacheStore store;
  late Dio dio;
  late DioAdapter adapter;
  late String account;

  setUp(() {
    store = MemCacheStore();
    httpCacheStore = store;
    account = 'user-1';
    dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    // AuthInterceptor's part: every request names the account it was sent as.
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.extra[kCacheSubjectExtra] = account;
      handler.next(options);
    }));
    // As createDioClient installs it.
    dio.interceptors.add(DioCacheInterceptor(
      options: CacheOptions(
        store: store,
        policy: CachePolicy.request,
        hitCacheOnErrorExcept: kNeverServeStaleFor,
        maxStale: const Duration(days: 7),
        keyBuilder: ntripiCacheKey,
      ),
    ));
    adapter = DioAdapter(dio: dio);
  });

  tearDown(() => httpCacheStore = null);

  Future<void> saveAnswering(String title) async {
    adapter.onPatch(
      itineraryStopEndpoint(_itinId, 'stop-1'),
      (server) =>
          server.reply(200, {'itinerary': _trip(title), 'created_id': null}),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
    );
    await ItineraryRepository(dio).updateStop(
      _itinId, 'stop-1', {'place_name': 'Old harbour'},
      etag: '"2026-10-21T10:00:00.000Z"', lockToken: 'lock-token',
    );
  }

  test('Given a save, Then the trip opened offline is the one it answered with',
      () async {
    // The copy the last download left, validators and all, as the server sends.
    adapter.onGet(
      itineraryEndpoint(_itinId),
      (server) => server.reply(200, _trip('Before the save'), headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'etag': ['"2026-10-21T10:00:00+00:00;0123456789abcdef"'],
        'cache-control': ['private, no-cache'],
      }),
    );
    await ItineraryRepository(dio).getItinerary(_itinId);
    await saveAnswering('After the save');

    dio.httpClientAdapter = _Offline();
    final shown = await ItineraryRepository(dio).getItinerary(_itinId);

    expect(shown.title, 'After the save');
  });

  test('Given a save, Then another account on the device finds no copy of it',
      () async {
    await saveAnswering('After the save');

    account = 'user-2';
    dio.httpClientAdapter = _Offline();

    await expectLater(ItineraryRepository(dio).getItinerary(_itinId),
        throwsA(isA<DioException>()));
  });
}
