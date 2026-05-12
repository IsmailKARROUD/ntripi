// test/repositories/itinerary_repository_test.dart — Unit tests for
// ItineraryRepository's reorder-related methods.
//
// Covers the HTTP contract for:
//   - PATCH /itineraries/{id}/stops/{stop_id} (Phase 1 + Phase 2c new-track)
//   - POST  /itineraries/{id}/reorder         (Phase 2a + Phase 2b)
//
// No real network — Dio is intercepted via http_mock_adapter. The tests pin
// the URL, body shape (including conditional inclusion of optional fields),
// and the mapping of 412 responses to ItineraryStaleException.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';

void main() {
  (Dio, DioAdapter) _makeDio() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final adapter = DioAdapter(dio: dio);
    return (dio, adapter);
  }

  // -------------------------------------------------------------------------
  // Fixtures
  // -------------------------------------------------------------------------

  const _itinId = 'itin-1';
  const _stopId = 'stop-1';
  const _etag = '"2026-05-11T10:22:56.909029Z"';

  /// Minimal Stop response body — matches Stop.fromJson expectations.
  Map<String, dynamic> _stopJson({
    String id = _stopId,
    String trackId = 't1',
  }) =>
      {
        'id': id,
        'itinerary_id': _itinId,
        'track_id': trackId,
        'rank': 'a0',
        'place_name': 'Paris',
        'place_address': null,
        'lat': null,
        'lng': null,
        'place_type': null,
        'duration_min': null,
        'cost': 0.0,
        'is_free': true,
        'notes': null,
        'created_at': '2026-05-11T10:22:56.909029Z',
        'annotations': <Map<String, dynamic>>[],
      };

  /// Minimal Itinerary response body — matches Itinerary.fromJson.
  Map<String, dynamic> _itineraryJson() => {
        'id': _itinId,
        'user_id': 'user-1',
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

  // -------------------------------------------------------------------------
  // updateStop — Phase 1 (existing-track move) + Phase 2c (new-track move)
  // -------------------------------------------------------------------------

  group('ItineraryRepository.updateStop', () {
    test('move-to-existing-track sends track_id and returns parsed Stop',
        () async {
      final (dio, adapter) = _makeDio();
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) => server.reply(200, _stopJson(trackId: 't2')),
        data: {'track_id': 't2'},
      );

      final repo = ItineraryRepository(dio);
      final stop = await repo.updateStop(
        _itinId,
        _stopId,
        {'track_id': 't2'},
        etag: _etag,
      );

      expect(stop.trackId, 't2');
      expect(stop.id, _stopId);
    });

    test('new-track-move body shape (Phase 2c) is forwarded as-is', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) => server.reply(200, _stopJson(trackId: 'new-track-id')),
        // Adapter matches the request body exactly — these keys must
        // appear verbatim in the request.
        data: {'after_track_id': 't1', 'before_track_id': 't2'},
      );

      final repo = ItineraryRepository(dio);
      final stop = await repo.updateStop(
        _itinId,
        _stopId,
        {'after_track_id': 't1', 'before_track_id': 't2'},
        etag: _etag,
      );

      expect(stop.trackId, 'new-track-id');
    });

    test('412 response throws ItineraryStaleException, not DioException',
        () async {
      final (dio, adapter) = _makeDio();
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) => server.reply(412, {'detail': 'itinerary modified'}),
        data: {'track_id': 't2'},
      );

      final repo = ItineraryRepository(dio);

      await expectLater(
        repo.updateStop(_itinId, _stopId, {'track_id': 't2'}, etag: _etag),
        throwsA(isA<ItineraryStaleException>()),
      );
    });

    test('If-Match header is sent on every PATCH', () async {
      final (dio, adapter) = _makeDio();
      // The adapter matches by data; we additionally rely on the request
      // history to verify the header was set.
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) => server.reply(200, _stopJson()),
        data: {'track_id': 't2'},
        headers: {'If-Match': _etag, 'content-type': 'application/json'},
      );

      final repo = ItineraryRepository(dio);
      // If the header doesn't match, the adapter returns 404 (no route),
      // which would bubble as a DioException. We assert success.
      await expectLater(
        repo.updateStop(_itinId, _stopId, {'track_id': 't2'}, etag: _etag),
        completes,
      );
    });
  });

  // -------------------------------------------------------------------------
  // reorderItinerary — Phase 2a/2b
  // -------------------------------------------------------------------------

  group('ItineraryRepository.reorderItinerary', () {
    test('stop_orders-only body returns parsed Itinerary', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, _itineraryJson()),
        data: {
          'stop_orders': {
            't1': ['s2', 's1'],
          },
        },
      );

      final repo = ItineraryRepository(dio);
      final itin = await repo.reorderItinerary(
        _itinId,
        stopOrders: {
          't1': ['s2', 's1'],
        },
        etag: _etag,
      );

      expect(itin.id, _itinId);
      expect(itin.title, 'Trip');
    });

    test('track_order + segments_to_delete body forwarded correctly',
        () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, _itineraryJson()),
        data: {
          'track_order': ['t3', 't1', 't2'],
          'segments_to_delete': ['seg-1'],
        },
      );

      final repo = ItineraryRepository(dio);
      final itin = await repo.reorderItinerary(
        _itinId,
        trackOrder: ['t3', 't1', 't2'],
        segmentIdsToDelete: ['seg-1'],
        etag: _etag,
      );

      expect(itin.id, _itinId);
    });

    test('empty optional fields are omitted from the body', () async {
      // The repo's body builder uses `if (xs != null && xs.isNotEmpty)` for
      // stop_orders and segments_to_delete; trackOrder uses `if (xs != null)`.
      // Passing only an empty stopOrders + null others → body is {}.
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, _itineraryJson()),
        data: <String, dynamic>{}, // exactly empty body expected
      );

      final repo = ItineraryRepository(dio);
      // Don't await — server-side would 422 in real flow; we only care that
      // the *client* sends the empty body it has built.
      await expectLater(
        repo.reorderItinerary(_itinId, stopOrders: {}, etag: _etag),
        completes,
      );
    });

    test('412 response throws ItineraryStaleException', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(412, {'detail': 'itinerary modified'}),
        data: {
          'stop_orders': {
            't1': ['s1'],
          },
        },
      );

      final repo = ItineraryRepository(dio);

      await expectLater(
        repo.reorderItinerary(
          _itinId,
          stopOrders: {
            't1': ['s1'],
          },
          etag: _etag,
        ),
        throwsA(isA<ItineraryStaleException>()),
      );
    });

    test('If-Match header is sent on every POST /reorder', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, _itineraryJson()),
        data: {
          'stop_orders': {
            't1': ['s1'],
          },
        },
        headers: {'If-Match': _etag, 'content-type': 'application/json'},
      );

      final repo = ItineraryRepository(dio);
      await expectLater(
        repo.reorderItinerary(
          _itinId,
          stopOrders: {
            't1': ['s1'],
          },
          etag: _etag,
        ),
        completes,
      );
    });
  });
}
