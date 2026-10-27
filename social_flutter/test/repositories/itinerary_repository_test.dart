// test/repositories/itinerary_repository_test.dart — Unit tests for
// ItineraryRepository's reorder-related methods.
//
// Covers the HTTP contract for:
//   - PATCH /itineraries/{id}/stops/{stop_id} (Phase 1 + Phase 2c new-track)
//   - POST  /itineraries/{id}/reorder         (Phase 2a + Phase 2b)
//
// No real network — Dio is intercepted via http_mock_adapter. The tests pin
// the URL, body shape (including conditional inclusion of optional fields),
// that each asks for the whole trip back, and the mapping of 412 responses to
// ItineraryStaleException.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';

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

  /// The trip with the stop alone on [trackId], as a stop edit answers with it.
  Map<String, dynamic> tripWithStop({String trackId = 't1'}) => {
        ..._itineraryJson(),
        'tracks': [
          {
            'id': trackId,
            'itinerary_id': _itinId,
            'rank': 'a0',
            'stops': [_stopJson(trackId: trackId)],
          },
        ],
      };

  /// What a trip edit answers when asked for the trip back.
  Map<String, dynamic> tripAnswer(Map<String, dynamic> trip) =>
      {'itinerary': trip, 'created_id': null};

  // -------------------------------------------------------------------------
  // updateStop — Phase 1 (existing-track move) + Phase 2c (new-track move)
  // -------------------------------------------------------------------------

  group('ItineraryRepository.getSharedWithMe', () {
    /// A shared-with-me row IS a feed row: the summary fields at the top level
    /// plus a nested `owner`. That is why FeedItem parses both.
    Map<String, dynamic> _sharedRowJson({
      String id = 'shared-1',
      String? displayName = 'Amina K.',
    }) =>
        {
          'id': id,
          'user_id': 'owner-9',
          'title': 'Tokyo run',
          'cover_image_url': null,
          'total_duration_min': 120,
          'total_cost': 0.0,
          'currency': 'JPY',
          'visibility': 'restricted',
          'created_at': '2026-08-12T10:22:56.909029Z',
          'updated_at': '2026-08-12T10:22:56.909029Z',
          'rating_avg': null,
          'rating_count': 0,
          'stops_count': 5,
          'owner': {
            'user_id': 'owner-9',
            'username': 'amina',
            'display_name': displayName,
            'avatar_url': null,
          },
        };

    test('Given granted trips, When called, Then parses trip and owner',
        () async {
      final (dio, adapter) = _makeDio();
      adapter.onGet(
        kSharedWithMeEndpoint,
        (server) => server.reply(200, [_sharedRowJson()]),
      );

      final repo = ItineraryRepository(dio);
      final items = await repo.getSharedWithMe();

      expect(items, hasLength(1));
      expect(items.first.itinerary.id, 'shared-1');
      expect(items.first.itinerary.stopsCount, 5);
      // The owner is the whole point — a restricted trip is in no feed and no
      // search, so the card has to say whose it is.
      expect(items.first.owner.username, 'amina');
      expect(items.first.owner.label, 'Amina K.');
    });

    test(
        'Given an owner with no display name, When called, '
        'Then the label falls back to the @handle', () async {
      final (dio, adapter) = _makeDio();
      adapter.onGet(
        kSharedWithMeEndpoint,
        (server) => server.reply(200, [_sharedRowJson(displayName: null)]),
      );

      final repo = ItineraryRepository(dio);
      final items = await repo.getSharedWithMe();

      expect(items.first.owner.label, '@amina');
    });

    test('Given no granted trips, When called, Then returns empty', () async {
      final (dio, adapter) = _makeDio();
      adapter.onGet(
        kSharedWithMeEndpoint,
        (server) => server.reply(200, <Map<String, dynamic>>[]),
      );

      final repo = ItineraryRepository(dio);

      expect(await repo.getSharedWithMe(), isEmpty);
    });

    test('Given the server fails, When called, Then the DioException surfaces',
        () async {
      final (dio, adapter) = _makeDio();
      adapter.onGet(
        kSharedWithMeEndpoint,
        (server) => server.reply(500, {'detail': 'boom'}),
      );

      final repo = ItineraryRepository(dio);

      // No swallow-to-empty here: the screen needs to tell "nothing shared
      // with you" apart from "we could not ask".
      await expectLater(
        repo.getSharedWithMe(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('ItineraryRepository.updateStop', () {
    test('move-to-existing-track sends track_id and answers with the trip, '
        'the stop moved', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) => server.reply(200, tripAnswer(tripWithStop(trackId: 't2'))),
        data: {'track_id': 't2'},
        queryParameters: {'return': 'itinerary'},
      );

      final repo = ItineraryRepository(dio);
      final answer = await repo.updateStop(
        _itinId,
        _stopId,
        {'track_id': 't2'},
        etag: _etag, lockToken: 'lock-token',
      );

      final stop = answer.itinerary!.stops.single;
      expect(stop.trackId, 't2');
      expect(stop.id, _stopId);
      expect(answer.createdId, isNull);
    });

    test('new-track-move body shape (Phase 2c) is forwarded as-is', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) =>
            server.reply(200, tripAnswer(tripWithStop(trackId: 'new-track-id'))),
        // Adapter matches the request body exactly — these keys must
        // appear verbatim in the request.
        data: {'after_track_id': 't1', 'before_track_id': 't2'},
      );

      final repo = ItineraryRepository(dio);
      final answer = await repo.updateStop(
        _itinId,
        _stopId,
        {'after_track_id': 't1', 'before_track_id': 't2'},
        etag: _etag, lockToken: 'lock-token',
      );

      expect(answer.itinerary!.stops.single.trackId, 'new-track-id');
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
        repo.updateStop(_itinId, _stopId, {'track_id': 't2'}, etag: _etag, lockToken: 'lock-token'),
        throwsA(isA<ItineraryStaleException>()),
      );
    });

    test('If-Match header is sent on every PATCH', () async {
      final (dio, adapter) = _makeDio();
      // The adapter matches by data; we additionally rely on the request
      // history to verify the header was set.
      adapter.onPatch(
        itineraryStopEndpoint(_itinId, _stopId),
        (server) => server.reply(200, tripAnswer(tripWithStop())),
        data: {'track_id': 't2'},
        headers: {'If-Match': _etag, 'content-type': 'application/json'},
      );

      final repo = ItineraryRepository(dio);
      // If the header doesn't match, the adapter returns 404 (no route),
      // which would bubble as a DioException. We assert success.
      await expectLater(
        repo.updateStop(_itinId, _stopId, {'track_id': 't2'}, etag: _etag, lockToken: 'lock-token'),
        completes,
      );
    });
  });

  // -------------------------------------------------------------------------
  // reorderItinerary — arrange mode's one save
  // -------------------------------------------------------------------------

  group('ItineraryRepository.reorderItinerary', () {
    const layout = [
      {
        'track_id': 't2',
        'stop_ids': ['s2', 's1'],
      },
      {
        'track_id': null,
        'stop_ids': ['s3'],
      },
    ];

    test('the layout body answers with the parsed trip', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, tripAnswer(_itineraryJson())),
        data: {'layout': layout},
        queryParameters: {'return': 'itinerary'},
      );

      final repo = ItineraryRepository(dio);
      final answer = await repo.reorderItinerary(
        _itinId,
        layout: layout,
        etag: _etag, lockToken: 'lock-token',
      );

      expect(answer.itinerary!.id, _itinId);
      expect(answer.itinerary!.title, 'Trip');
    });

    test('segments the layout breaks ride in the same body', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, tripAnswer(_itineraryJson())),
        data: {
          'layout': layout,
          'segments_to_delete': ['seg-1'],
        },
      );

      final repo = ItineraryRepository(dio);
      final answer = await repo.reorderItinerary(
        _itinId,
        layout: layout,
        segmentIdsToDelete: ['seg-1'],
        etag: _etag, lockToken: 'lock-token',
      );

      expect(answer.itinerary!.id, _itinId);
    });

    test('an empty segment list is left out of the body', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, tripAnswer(_itineraryJson())),
        data: {'layout': layout}, // exactly this body expected
      );

      final repo = ItineraryRepository(dio);
      await expectLater(
        repo.reorderItinerary(_itinId,
            layout: layout,
            segmentIdsToDelete: const [],
            etag: _etag,
            lockToken: 'lock-token'),
        completes,
      );
    });

    test('412 response throws ItineraryStaleException', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(412, {'detail': 'itinerary modified'}),
        data: {'layout': layout},
      );

      final repo = ItineraryRepository(dio);

      await expectLater(
        repo.reorderItinerary(
          _itinId,
          layout: layout,
          etag: _etag, lockToken: 'lock-token',
        ),
        throwsA(isA<ItineraryStaleException>()),
      );
    });

    test('If-Match header is sent on every POST /reorder', () async {
      final (dio, adapter) = _makeDio();
      adapter.onPost(
        itineraryReorderEndpoint(_itinId),
        (server) => server.reply(200, tripAnswer(_itineraryJson())),
        data: {'layout': layout},
        headers: {'If-Match': _etag, 'content-type': 'application/json'},
      );

      final repo = ItineraryRepository(dio);
      await expectLater(
        repo.reorderItinerary(
          _itinId,
          layout: layout,
          etag: _etag, lockToken: 'lock-token',
        ),
        completes,
      );
    });
  });
}
