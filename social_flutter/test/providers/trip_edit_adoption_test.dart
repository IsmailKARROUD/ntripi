// test/providers/trip_edit_adoption_test.dart — a trip save is its only request.
//
// Every trip edit asks for the whole trip back (`?return=itinerary`) and
// ItineraryDetailNotifier adopts it: nothing downloads the trip again after a
// save, so the trip view is never rebuilt behind a reload, and the next save
// carries the answered stamp. A rating's answer carries the trip's new average
// and count the same way. Run against the real repository on a mocked Dio, so
// "one request" is an exact assertion rather than an absence of errors.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/my_rating.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/itinerary_unavailable_view.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';

const _itinId = 'itin-1';
const _loadedAt = '2026-10-21T10:00:00.000000Z';
const _answeredAt = '2026-10-21T10:00:05.123456Z';
const _returnTrip = {'return': 'itinerary'};

Map<String, dynamic> _stop(String id, String trackId) => {
      'id': id,
      'itinerary_id': _itinId,
      'track_id': trackId,
      'rank': 'a0',
      'place_name': 'Harbour',
      'place_address': null,
      'lat': null,
      'lng': null,
      'map_url': null,
      'place_type': null,
      'duration_min': null,
      'cost': 0.0,
      'is_free': true,
      'notes': null,
      'created_at': '2026-10-21T09:00:00.000000Z',
      'annotations': <Map<String, dynamic>>[],
    };

/// The detail as the GET shows it. The answered one differs in title, stamp,
/// stops and aggregate, so adopting it is visible in every one of them.
Map<String, dynamic> _trip({bool answered = false}) => {
      'id': _itinId,
      'user_id': 'user-1',
      'title': answered ? 'Answered' : 'Coast walk',
      'cover_image_url': null,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-21T09:00:00.000000Z',
      'updated_at': answered ? _answeredAt : _loadedAt,
      'rating_avg': answered ? 3.5 : 4.0,
      'rating_count': answered ? 2 : 1,
      'stops_count': answered ? 2 : 1,
      'description': null,
      'tracks': [
        {
          'id': 't1',
          'itinerary_id': _itinId,
          'rank': 'a0',
          'stops': [_stop('stop-1', 't1')],
        },
        if (answered)
          {
            'id': 't2',
            'itinerary_id': _itinId,
            'rank': 'b',
            'stops': [_stop('stop-new', 't2')],
          },
      ],
      'segments': <Map<String, dynamic>>[],
      'annotations': <Map<String, dynamic>>[],
      'can_edit': true,
    };

/// What a test compares: everything adopting the answer changes.
Map<String, Object?> _shape(Itinerary trip) => {
      'title': trip.title,
      'updatedAt': trip.updatedAt,
      'eTag': trip.eTag,
      'stops': [for (final s in trip.stops) '${s.trackId}/${s.id}'],
      'ratingAvg': trip.ratingAvg,
      'ratingCount': trip.ratingCount,
    };

/// A claim held by this device, without the network or the heartbeat.
class _HeldClaim extends EditLockNotifier {
  _HeldClaim(super.arg);

  @override
  EditSession build() {
    super.build();
    return const EditSession(token: 'lock-token');
  }
}

/// One of the notifier's trip saves: the request it must send, and the call.
class _Save {
  const _Save(this.name, this.method, this.path, this.run, {this.createdId});

  final String name;
  final String method;
  final String path;
  final Future<void> Function(ItineraryDetailNotifier notifier) run;
  final String? createdId;
}

final _saves = <_Save>[
  _Save('addStop', 'POST', itineraryStopsEndpoint(_itinId),
      (n) => n.addStop({'place_name': 'Cove', 'track_id': 't1'}),
      createdId: 'stop-new'),
  _Save('updateStop', 'PATCH', itineraryStopEndpoint(_itinId, 'stop-1'),
      (n) => n.updateStop('stop-1', {'place_name': 'Old harbour'})),
  _Save('moveStop', 'PATCH', itineraryStopEndpoint(_itinId, 'stop-1'),
      (n) => n.moveStop('stop-1', targetTrackId: 't2')),
  _Save('deleteStop', 'DELETE', itineraryStopEndpoint(_itinId, 'stop-1'),
      (n) => n.deleteStop('stop-1')),
  _Save('applyReorder', 'POST', itineraryReorderEndpoint(_itinId),
      (n) => n.applyReorder(trackOrder: ['t1'])),
  _Save('updateHeader', 'PATCH', itineraryEndpoint(_itinId),
      (n) => n.updateHeader({'description': 'Shorter.'})),
  _Save('saveForm', 'PATCH', itineraryFormEndpoint(_itinId),
      (n) => n.saveForm({'title': 'Answered'})),
  _Save('createSegment', 'POST', itinerarySegmentsEndpoint(_itinId),
      (n) => n.createSegment({
            'from_stop_id': 'stop-1',
            'to_stop_id': 'stop-new',
            'legs': [
              {'position': 1, 'mode': 'walk'},
            ],
          }),
      createdId: 'seg-new'),
  _Save('updateSegment', 'PATCH', itinerarySegmentEndpoint(_itinId, 'seg-1'),
      (n) => n.updateSegment('seg-1', {
            'from_stop_id': 'stop-1',
            'to_stop_id': 'stop-new',
            'legs': [
              {'position': 1, 'mode': 'bus'},
            ],
          })),
  _Save('deleteSegment', 'DELETE', itinerarySegmentEndpoint(_itinId, 'seg-1'),
      (n) => n.deleteSegment('seg-1')),
  _Save('addAnnotation', 'POST', stopAnnotationsEndpoint(_itinId, 'stop-1'),
      (n) => n.addAnnotation('stop-1', {'type': 'info', 'content': 'Go early'}),
      createdId: 'note-new'),
  _Save('updateAnnotation', 'PATCH',
      stopAnnotationEndpoint(_itinId, 'stop-1', 'note-1'),
      (n) => n.updateAnnotation('stop-1', 'note-1', content: 'Go at dawn')),
  _Save('deleteAnnotation', 'DELETE',
      stopAnnotationEndpoint(_itinId, 'stop-1', 'note-1'),
      (n) => n.deleteAnnotation('stop-1', 'note-1')),
  _Save('addItineraryAnnotation', 'POST', itineraryAnnotationsEndpoint(_itinId),
      (n) => n.addItineraryAnnotation({'type': 'info', 'content': 'Bring cash'}),
      createdId: 'trip-note-new'),
  _Save('updateItineraryAnnotation', 'PATCH',
      itineraryAnnotationEndpoint(_itinId, 'trip-note-1'),
      (n) => n.updateItineraryAnnotation('trip-note-1', content: 'More cash')),
  _Save('deleteItineraryAnnotation', 'DELETE',
      itineraryAnnotationEndpoint(_itinId, 'trip-note-1'),
      (n) => n.deleteItineraryAnnotation('trip-note-1')),
];

void main() {
  late DioAdapter adapter;
  late List<RequestOptions> sent;
  late ProviderContainer container;

  List<String> lines() => sent.map((o) => '${o.method} ${o.path}').toList();

  /// The real repository on a mocked Dio that logs every request it sends.
  void connect() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    adapter = DioAdapter(dio: dio);
    sent = [];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.next(options);
    }));
    adapter.onGet(
        itineraryEndpoint(_itinId), (server) => server.reply(200, _trip()));
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(dio)),
      editLockProvider.overrideWith2(_HeldClaim.new),
    ]);
  }

  /// The detail screen's first load, then a clean request log.
  Future<ItineraryDetailNotifier> load() async {
    connect();
    await container.read(itineraryDetailProvider(_itinId).future);
    sent.clear();
    return container.read(itineraryDetailProvider(_itinId).notifier);
  }

  /// [save]'s route answers with [body] — when it carries the opt-in.
  void answer(_Save save, Object body, {int status = 200}) {
    switch (save.method) {
      case 'POST':
        adapter.onPost(save.path, (server) => server.reply(status, body),
            data: Matchers.any, queryParameters: _returnTrip);
      case 'PATCH':
        adapter.onPatch(save.path, (server) => server.reply(status, body),
            data: Matchers.any, queryParameters: _returnTrip);
      case 'DELETE':
        adapter.onDelete(save.path, (server) => server.reply(status, body),
            data: Matchers.any, queryParameters: _returnTrip);
    }
  }

  Itinerary detail() => container.read(itineraryDetailProvider(_itinId)).value!;

  tearDown(() => container.dispose());

  group('every trip save is one request, and its answer is the trip', () {
    for (final save in _saves) {
      test(save.name, () async {
        final notifier = await load();
        answer(save, {'itinerary': _trip(answered: true), 'created_id': save.createdId});

        await save.run(notifier);

        expect(lines(), ['${save.method} ${save.path}'], reason: 'no reload');
        expect(sent.single.queryParameters, _returnTrip);
        expect(_shape(detail()), _shape(Itinerary.fromJson(_trip(answered: true))));
        expect(notifier.hasWritesInFlight, isFalse);
      });
    }
  });

  test('addStop returns the stop the answer names, wherever it ranks', () async {
    final notifier = await load();
    answer(_saves.first, {'itinerary': _trip(answered: true), 'created_id': 'stop-new'});

    final created = await notifier.addStop({'place_name': 'Cove'});

    expect((created.id, created.trackId), ('stop-new', 't2'));
  });

  test('the answered stamp is the next If-Match', () async {
    final notifier = await load();
    final update = _saves.firstWhere((s) => s.name == 'updateStop');
    answer(update, {'itinerary': _trip(answered: true), 'created_id': null});

    await notifier.updateStop('stop-1', {'place_name': 'Old harbour'});
    await notifier.updateStop('stop-1', {'place_name': 'Older harbour'});

    expect(sent.first.headers['If-Match'], Itinerary.fromJson(_trip()).eTag);
    expect(sent.last.headers['If-Match'],
        Itinerary.fromJson(_trip(answered: true)).eTag);
  });

  test('a 412 adopts nothing: the trip and its ETag stay as loaded', () async {
    final notifier = await load();
    final loaded = _shape(detail());
    answer(_saves.first,
        {'detail': 'itinerary modified, please reload', 'code': 'itinerary_stale'},
        status: 412);

    await expectLater(notifier.addStop({'place_name': 'Cove'}),
        throwsA(isA<ItineraryStaleException>()));

    expect(lines(), ['POST ${itineraryStopsEndpoint(_itinId)}']);
    expect(_shape(detail()), loaded);
    expect(notifier.hasWritesInFlight, isFalse);
  });

  group('a save that takes the viewer\'s access away answers no trip', () {
    void refusedOnReload() => adapter.onGet(
          itineraryEndpoint(_itinId),
          (server) => server.reply(403, {
            'detail': "You don't have access to this itinerary",
            'code': 'itinerary_access_denied',
          }),
        );

    test('the GET\'s refusal puts the screen in its no-access state', () async {
      final notifier = await load();
      answer(_saves.firstWhere((s) => s.name == 'deleteStop'),
          {'itinerary': null, 'created_id': null});
      refusedOnReload();

      await notifier.deleteStop('stop-1');

      expect(lines(), [
        'DELETE ${itineraryStopEndpoint(_itinId, 'stop-1')}',
        'GET ${itineraryEndpoint(_itinId)}',
      ]);
      final state = container.read(itineraryDetailProvider(_itinId));
      expect(itineraryUnavailableFrom(state.error!), ItineraryUnavailable.noAccess);
    });

    test('a save its caller needs a trip back from rethrows that refusal',
        () async {
      final notifier = await load();
      answer(_saves.first, {'itinerary': null, 'created_id': 'stop-new'});
      refusedOnReload();

      await expectLater(
        notifier.addStop({'place_name': 'Cove'}),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 403)),
      );
    });
  });

  group('a rating adopts the trip\'s new aggregate', () {
    const myRating = {
      'stars': 3,
      'safety_stars': null,
      'experience_stars': null,
      'accessibility_stars': null,
      'family_friendly_stars': null,
      'crowdedness_stars': null,
      'note': null,
      'updated_at': '2026-10-21T10:00:09.000000Z',
      'moderation_status': 'approved',
    };

    /// My rating's first read, then a clean request log.
    Future<MyRatingNotifier> rater() async {
      adapter.onGet(itineraryMyRatingEndpoint(_itinId),
          (server) => server.reply(404, {'detail': 'not rated'}));
      await container.read(myRatingProvider(_itinId).future);
      sent.clear();
      return container.read(myRatingProvider(_itinId).notifier);
    }

    test('submitting one updates the average without a GET', () async {
      await load();
      final loaded = detail();
      final notifier = await rater();
      adapter.onPost(
        itineraryRatingsEndpoint(_itinId),
        (server) => server.reply(
            201, {...myRating, 'rating_avg': 3.5, 'rating_count': 2}),
        data: Matchers.any,
      );

      await notifier.submitRating(const MyRating(stars: 3));

      expect(lines(), ['POST ${itineraryRatingsEndpoint(_itinId)}']);
      expect((detail().ratingAvg, detail().ratingCount), (3.5, 2));
      // The aggregate never moves updated_at, so neither does the ETag.
      expect(detail().eTag, loaded.eTag);
    });

    test('deleting the last one clears the average without a GET', () async {
      await load();
      final notifier = await rater();
      adapter.onDelete(
        itineraryMyRatingEndpoint(_itinId),
        (server) => server.reply(200, {'rating_avg': null, 'rating_count': 0}),
        queryParameters: {'return': 'aggregate'},
      );

      await notifier.deleteRating();

      expect(lines(), ['DELETE ${itineraryMyRatingEndpoint(_itinId)}']);
      expect(sent.single.queryParameters, {'return': 'aggregate'});
      expect((detail().ratingAvg, detail().ratingCount), (null, 0));
    });

    test('with no trip loaded, nothing is fetched to put it on', () async {
      connect();
      final notifier = await rater();
      adapter.onPost(
        itineraryRatingsEndpoint(_itinId),
        (server) => server.reply(
            201, {...myRating, 'rating_avg': 3.5, 'rating_count': 2}),
        data: Matchers.any,
      );

      await notifier.submitRating(const MyRating(stars: 3));

      expect(lines(), ['POST ${itineraryRatingsEndpoint(_itinId)}']);
      expect(container.exists(itineraryDetailProvider(_itinId)), isFalse);
    });
  });
}
