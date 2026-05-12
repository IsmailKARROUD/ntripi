// test/repositories/force_refresh_test.dart — verifies that every GET method
// reachable from a `.refresh()` callback can opt into bypassing the
// dio_cache_interceptor's conditional-GET validator via `forceRefresh: true`.
//
// Why this matters: with CachePolicy.request as the global default, every
// GET sends `If-None-Match` and may come back as a 304. Pull-to-refresh and
// error-state Retry need to short-circuit that and force a full server fetch.
// The contract is: `forceRefresh: true` attaches `CacheOptions(policy:
// CachePolicy.refresh)` to the request's `Options.extra`; `forceRefresh: false`
// (the default) attaches nothing.
//
// We assert on the actual Dio RequestOptions captured by a tiny interceptor,
// then read it back with `CacheOptions.fromExtra(...)` — the same API the
// real cache interceptor uses. No mocking of the interceptor itself.

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';

/// Captures the outgoing RequestOptions so each test can inspect whether the
/// cache-policy override was attached. Installed before the mock adapter so
/// it sees the request first.
class _CaptureInterceptor extends Interceptor {
  RequestOptions? captured;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    captured = options;
    handler.next(options);
  }
}

(Dio, DioAdapter, _CaptureInterceptor) _makeDio() {
  final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
  final capture = _CaptureInterceptor();
  dio.interceptors.add(capture);
  final adapter = DioAdapter(dio: dio);
  return (dio, adapter, capture);
}

const _userId = 'user-1';
const _itinId = 'itin-1';

/// Minimal Itinerary body — matches Itinerary.fromJson.
Map<String, dynamic> _itineraryJson() => {
      'id': _itinId,
      'user_id': _userId,
      'title': 'Trip',
      'description': null,
      'cover_image_url': null,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'only_me',
      'created_at': '2026-05-11T10:22:56.909029Z',
      'updated_at': '2026-05-11T11:00:00.000000Z',
      'rating_avg': null,
      'rating_count': 0,
      'tracks': <Map<String, dynamic>>[],
      'segments': <Map<String, dynamic>>[],
      'annotations': <Map<String, dynamic>>[],
      'stops_count': 0,
    };

Map<String, dynamic> _ratingsPageJson() => {
      'rating_avg': null,
      'rating_count': 0,
      'distribution': {'five': 0, 'four': 0, 'three': 0, 'two': 0, 'one': 0},
      'ratings': <Map<String, dynamic>>[],
    };

Map<String, dynamic> _followRequestJson() => {
      'follow_id': 'fr-1',
      'follower_id': 'user-2',
      'username': 'bob',
      'requested_at': '2026-05-11T10:22:56.909029Z',
    };

Map<String, dynamic> _followerListItemJson() => {
      'id': 'user-2',
      'username': 'bob',
      'is_private': false,
    };

/// Reads the cache policy out of the captured request's extra map. Returns
/// null when no override was attached — that's the "default" path the test
/// relies on to confirm the conditional-GET validator stays in play.
CachePolicy? _capturedPolicy(_CaptureInterceptor capture) {
  expect(capture.captured, isNotNull,
      reason: 'request never reached the interceptor');
  return CacheOptions.fromExtra(capture.captured!)?.policy;
}

void main() {
  // ---------------------------------------------------------------------------
  // ItineraryRepository — the four GETs reachable from `.refresh()` callbacks.
  // ---------------------------------------------------------------------------

  group('ItineraryRepository forceRefresh', () {
    group('getMyItineraries', () {
      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          kMyItinerariesEndpoint,
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await ItineraryRepository(dio).getMyItineraries();

        expect(_capturedPolicy(capture), isNull);
      });

      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          kMyItinerariesEndpoint,
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await ItineraryRepository(dio).getMyItineraries(forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });
    });

    group('getItinerary', () {
      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          itineraryEndpoint(_itinId),
          (server) => server.reply(200, _itineraryJson()),
        );

        await ItineraryRepository(dio).getItinerary(_itinId);

        expect(_capturedPolicy(capture), isNull);
      });

      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          itineraryEndpoint(_itinId),
          (server) => server.reply(200, _itineraryJson()),
        );

        await ItineraryRepository(dio)
            .getItinerary(_itinId, forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });
    });

    group('getUserItineraries', () {
      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          userItinerariesEndpoint(_userId),
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await ItineraryRepository(dio)
            .getUserItineraries(_userId, forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });

      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          userItinerariesEndpoint(_userId),
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await ItineraryRepository(dio).getUserItineraries(_userId);

        expect(_capturedPolicy(capture), isNull);
      });
    });

    group('getRatingsPage', () {
      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          itineraryRatingsEndpoint(_itinId),
          (server) => server.reply(200, _ratingsPageJson()),
        );

        await ItineraryRepository(dio)
            .getRatingsPage(_itinId, forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });

      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          itineraryRatingsEndpoint(_itinId),
          (server) => server.reply(200, _ratingsPageJson()),
        );

        await ItineraryRepository(dio).getRatingsPage(_itinId);

        expect(_capturedPolicy(capture), isNull);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // FollowRepository — the three GETs reachable from `.refresh()` callbacks.
  // ---------------------------------------------------------------------------

  group('FollowRepository forceRefresh', () {
    group('getFollowRequests', () {
      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          kFollowRequestsEndpoint,
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await FollowRepository(dio).getFollowRequests();

        expect(_capturedPolicy(capture), isNull);
      });

      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          kFollowRequestsEndpoint,
          (server) => server.reply(200, [_followRequestJson()]),
        );

        await FollowRepository(dio).getFollowRequests(forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });
    });

    group('getFollowers', () {
      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          followersEndpoint(_userId),
          (server) => server.reply(200, [_followerListItemJson()]),
        );

        await FollowRepository(dio).getFollowers(_userId, forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });

      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          followersEndpoint(_userId),
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await FollowRepository(dio).getFollowers(_userId);

        expect(_capturedPolicy(capture), isNull);
      });
    });

    group('getFollowing', () {
      test(
          'Given forceRefresh: true, '
          'When called, '
          'Then CachePolicy.refresh is attached to the request', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          followingEndpoint(_userId),
          (server) => server.reply(200, [_followerListItemJson()]),
        );

        await FollowRepository(dio).getFollowing(_userId, forceRefresh: true);

        expect(_capturedPolicy(capture), CachePolicy.refresh);
      });

      test(
          'Given default args, '
          'When called, '
          'Then no cache-policy override is attached', () async {
        final (dio, adapter, capture) = _makeDio();
        adapter.onGet(
          followingEndpoint(_userId),
          (server) => server.reply(200, <Map<String, dynamic>>[]),
        );

        await FollowRepository(dio).getFollowing(_userId);

        expect(_capturedPolicy(capture), isNull);
      });
    });
  });
}
