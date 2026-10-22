// test/providers/trip_edit_adoption_test.dart — a trip save is its only request.
//
// Every trip edit asks for the whole trip back (`?return=itinerary`) and
// ItineraryDetailNotifier adopts it: nothing downloads the trip again after a
// save, so the trip view is never rebuilt behind a reload, and the next save
// carries the answered stamp. The trip's row in the Itineraries tab follows the
// same answer, and a create's answer is what the new trip's screen opens on. A
// rating's answer carries the trip's new average and count the same way — and
// the ratings page, when it is open. Run against the real repository on a
// mocked Dio, so "one request" is an exact assertion rather than an absence of
// errors.

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

import '../support/held_claim.dart';
import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _returnTrip = {'return': 'itinerary'};

/// The detail as the GET shows it. The answered one differs in title, stamp,
/// stops, totals and aggregate, so adopting it is visible in every one of them.
Map<String, dynamic> _trip({bool answered = false}) => tripJson(
      title: answered ? 'Answered' : 'Coast walk',
      updatedAt: answered ? kSavedAt : kLoadedAt,
      totalDurationMin: answered ? 95 : 0,
      totalCost: answered ? 12.5 : 0.0,
      ratingAvg: answered ? 3.5 : 4.0,
      ratingCount: answered ? 2 : 1,
      tracks: [
        trackJson('t1', [stopJson('stop-1')]),
        if (answered)
          trackJson('t2', [stopJson('stop-new', trackId: 't2')], rank: 'b'),
      ],
    );

/// What a test compares: everything adopting the answer changes.
Map<String, Object?> _shape(Itinerary trip) => {
      'title': trip.title,
      'updatedAt': trip.updatedAt,
      'eTag': trip.eTag,
      'stops': [for (final s in trip.stops) '${s.trackId}/${s.id}'],
      'ratingAvg': trip.ratingAvg,
      'ratingCount': trip.ratingCount,
    };

/// What a list row shows of a trip.
Map<String, Object?> _row(Itinerary trip) => {
      'title': trip.title,
      'updatedAt': trip.updatedAt,
      'stopsCount': trip.stopsCount,
      'totals': (trip.totalDurationMin, trip.totalCost),
      'rating': (trip.ratingAvg, trip.ratingCount),
    };

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
  _Save('addStop', 'POST', itineraryStopsEndpoint(kTripId),
      (n) => n.addStop({'place_name': 'Cove', 'track_id': 't1'}),
      createdId: 'stop-new'),
  _Save('updateStop', 'PATCH', itineraryStopEndpoint(kTripId, 'stop-1'),
      (n) => n.updateStop('stop-1', {'place_name': 'Old harbour'})),
  _Save('moveStop', 'PATCH', itineraryStopEndpoint(kTripId, 'stop-1'),
      (n) => n.moveStop('stop-1', targetTrackId: 't2')),
  _Save('deleteStop', 'DELETE', itineraryStopEndpoint(kTripId, 'stop-1'),
      (n) => n.deleteStop('stop-1')),
  _Save('applyReorder', 'POST', itineraryReorderEndpoint(kTripId),
      (n) => n.applyReorder(trackOrder: ['t1'])),
  _Save('updateHeader', 'PATCH', itineraryEndpoint(kTripId),
      (n) => n.updateHeader({'description': 'Shorter.'})),
  _Save('saveForm', 'PATCH', itineraryFormEndpoint(kTripId),
      (n) => n.saveForm({'title': 'Answered'})),
  _Save('createSegment', 'POST', itinerarySegmentsEndpoint(kTripId),
      (n) => n.createSegment({
            'from_stop_id': 'stop-1',
            'to_stop_id': 'stop-new',
            'legs': [
              {'position': 1, 'mode': 'walk'},
            ],
          }),
      createdId: 'seg-new'),
  _Save('updateSegment', 'PATCH', itinerarySegmentEndpoint(kTripId, 'seg-1'),
      (n) => n.updateSegment('seg-1', {
            'from_stop_id': 'stop-1',
            'to_stop_id': 'stop-new',
            'legs': [
              {'position': 1, 'mode': 'bus'},
            ],
          })),
  _Save('deleteSegment', 'DELETE', itinerarySegmentEndpoint(kTripId, 'seg-1'),
      (n) => n.deleteSegment('seg-1')),
  _Save('addAnnotation', 'POST', stopAnnotationsEndpoint(kTripId, 'stop-1'),
      (n) => n.addAnnotation('stop-1', {'type': 'info', 'content': 'Go early'}),
      createdId: 'note-new'),
  _Save('updateAnnotation', 'PATCH',
      stopAnnotationEndpoint(kTripId, 'stop-1', 'note-1'),
      (n) => n.updateAnnotation('stop-1', 'note-1', content: 'Go at dawn')),
  _Save('deleteAnnotation', 'DELETE',
      stopAnnotationEndpoint(kTripId, 'stop-1', 'note-1'),
      (n) => n.deleteAnnotation('stop-1', 'note-1')),
  _Save('addItineraryAnnotation', 'POST', itineraryAnnotationsEndpoint(kTripId),
      (n) => n.addItineraryAnnotation({'type': 'info', 'content': 'Bring cash'}),
      createdId: 'trip-note-new'),
  _Save('updateItineraryAnnotation', 'PATCH',
      itineraryAnnotationEndpoint(kTripId, 'trip-note-1'),
      (n) => n.updateItineraryAnnotation('trip-note-1', content: 'More cash')),
  _Save('deleteItineraryAnnotation', 'DELETE',
      itineraryAnnotationEndpoint(kTripId, 'trip-note-1'),
      (n) => n.deleteItineraryAnnotation('trip-note-1')),
];

void main() {
  late DioAdapter adapter;
  late List<RequestOptions> sent;
  late ProviderContainer container;

  List<String> lines() => sent.map((o) => '${o.method} ${o.path}').toList();

  /// The real repository on a mocked Dio that logs every request it sends.
  void connect() {
    final api = RecordingDio();
    adapter = api.adapter;
    sent = api.sent;
    adapter.onGet(
        itineraryEndpoint(kTripId), (server) => server.reply(200, _trip()));
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(api.dio)),
      editLockProvider.overrideWith2(HeldClaim.new),
    ]);
  }

  /// The detail screen's first load, then a clean request log.
  Future<ItineraryDetailNotifier> load() async {
    connect();
    await container.read(itineraryDetailProvider(kTripId).future);
    sent.clear();
    return container.read(itineraryDetailProvider(kTripId).notifier);
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

  Itinerary detail() => container.read(itineraryDetailProvider(kTripId)).value!;

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

  group('every save leaves its answer in the Itineraries tab, and no list GET',
      () {
    /// The Mine list as the tab loaded it, then a clean request log.
    Future<void> mine() async {
      adapter.onGet(kMyItinerariesEndpoint,
          (server) => server.reply(200, [summaryJson(stopsCount: 1)]));
      await container.read(myItinerariesProvider.future);
      sent.clear();
    }

    for (final save in _saves) {
      test(save.name, () async {
        final notifier = await load();
        await mine();
        answer(save, tripAnswer(_trip(answered: true), createdId: save.createdId));

        await save.run(notifier);

        expect(lines(), ['${save.method} ${save.path}'], reason: 'no list reload');
        final row = container.read(myItinerariesProvider).value!.single;
        expect(_row(row), _row(Itinerary.fromJson(_trip(answered: true))));
        expect(row.tracks, isEmpty, reason: 'a row holds the summary');
      });
    }

    test("an editor's save updates their Shared row and keeps whose trip it is",
        () async {
      final notifier = await load();
      adapter.onGet(kSharedWithMeEndpoint, (server) => server.reply(
          200, [sharedRowJson(summaryJson(stopsCount: 1))]));
      await container.read(sharedWithMeProvider.future);
      sent.clear();
      final update = _saves.firstWhere((s) => s.name == 'updateSegment');
      answer(update, tripAnswer(_trip(answered: true)));

      await update.run(notifier);

      expect(lines(), ['${update.method} ${update.path}']);
      final item = container.read(sharedWithMeProvider).value!.single;
      expect(_row(item.itinerary), _row(Itinerary.fromJson(_trip(answered: true))));
      expect(item.owner.username, 'tripowner');
    });
  });

  test('a create opens its trip with no GET of it', () async {
    connect();
    adapter
      ..onGet(kMyItinerariesEndpoint, (server) => server.reply(200, <Object>[]))
      ..onPost(
        kItinerariesEndpoint,
        (server) => server.reply(
            201, tripAnswer(_trip(answered: true), createdId: kTripId)),
        data: Matchers.any,
        queryParameters: _returnTrip,
      );
    await container.read(myItinerariesProvider.future);
    sent.clear();

    final id = await container
        .read(myItinerariesProvider.notifier)
        .addItinerary({'title': 'Answered'});
    final opened = await container.read(itineraryDetailProvider(id).future);

    expect(lines(), ['POST $kItinerariesEndpoint']);
    expect(_shape(opened), _shape(Itinerary.fromJson(_trip(answered: true))));
    expect(container.read(myItinerariesProvider).value!.single.id, id);

    // Taken once: Retry or pull-to-refresh downloads, as it must.
    container.invalidate(itineraryDetailProvider(id));
    await container.read(itineraryDetailProvider(id).future);
    expect(lines().last, 'GET ${itineraryEndpoint(kTripId)}');
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

    expect(lines(), ['POST ${itineraryStopsEndpoint(kTripId)}']);
    expect(_shape(detail()), loaded);
    expect(notifier.hasWritesInFlight, isFalse);
  });

  group('a save that takes the viewer\'s access away answers no trip', () {
    void refusedOnReload() => adapter.onGet(
          itineraryEndpoint(kTripId),
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
        'DELETE ${itineraryStopEndpoint(kTripId, 'stop-1')}',
        'GET ${itineraryEndpoint(kTripId)}',
      ]);
      final state = container.read(itineraryDetailProvider(kTripId));
      expect(itineraryUnavailableFrom(state.error!), ItineraryUnavailable.noAccess);
    });

    test('and Shared with me no longer lists the trip', () async {
      final notifier = await load();
      adapter.onGet(kSharedWithMeEndpoint, (server) => server.reply(
          200, [sharedRowJson(summaryJson(stopsCount: 1))]));
      await container.read(sharedWithMeProvider.future);
      sent.clear();
      answer(_saves.firstWhere((s) => s.name == 'deleteStop'), tripAnswer(null));
      refusedOnReload();

      await notifier.deleteStop('stop-1');

      expect(container.read(sharedWithMeProvider).value, isEmpty);
      // The trip's refusal is the one GET; the list is not downloaded again.
      expect(lines(), [
        'DELETE ${itineraryStopEndpoint(kTripId, 'stop-1')}',
        'GET ${itineraryEndpoint(kTripId)}',
      ]);
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
      adapter.onGet(itineraryMyRatingEndpoint(kTripId),
          (server) => server.reply(404, {'detail': 'not rated'}));
      await container.read(myRatingProvider(kTripId).future);
      sent.clear();
      return container.read(myRatingProvider(kTripId).notifier);
    }

    test('submitting one updates the average without a GET', () async {
      await load();
      final loaded = detail();
      final notifier = await rater();
      adapter.onPost(
        itineraryRatingsEndpoint(kTripId),
        (server) => server.reply(
            201, {...myRating, 'rating_avg': 3.5, 'rating_count': 2}),
        data: Matchers.any,
      );

      await notifier.submitRating(const MyRating(stars: 3));

      expect(lines(), ['POST ${itineraryRatingsEndpoint(kTripId)}']);
      expect((detail().ratingAvg, detail().ratingCount), (3.5, 2));
      // The aggregate never moves updated_at, so neither does the ETag.
      expect(detail().eTag, loaded.eTag);
    });

    test('deleting the last one clears the average without a GET', () async {
      await load();
      final notifier = await rater();
      adapter.onDelete(
        itineraryMyRatingEndpoint(kTripId),
        (server) => server.reply(200, {'rating_avg': null, 'rating_count': 0}),
        queryParameters: {'return': 'aggregate'},
      );

      await notifier.deleteRating();

      expect(lines(), ['DELETE ${itineraryMyRatingEndpoint(kTripId)}']);
      expect(sent.single.queryParameters, {'return': 'aggregate'});
      expect((detail().ratingAvg, detail().ratingCount), (null, 0));
    });

    /// The ratings page as GET /ratings shows it, holding [count] reviews.
    Map<String, dynamic> page(int count, double? avg) => {
          'rating_avg': avg,
          'rating_count': count,
          'distribution': {'five': 0, 'four': 0, 'three': count, 'two': 0, 'one': 0},
          'ratings': <Map<String, dynamic>>[],
        };

    /// The ratings page as its screen loaded it, then a clean request log.
    Future<void> ratingsPageOpen() async {
      adapter.onGet(itineraryRatingsEndpoint(kTripId),
          (server) => server.reply(200, page(1, 4.0)));
      await container.read(ratingsPageProvider(kTripId).future);
      sent.clear();
    }

    test('rated from the open ratings page, the page is adopted, not fetched',
        () async {
      await load();
      final notifier = await rater();
      await ratingsPageOpen();
      adapter.onPost(
        itineraryRatingsEndpoint(kTripId),
        (server) => server.reply(201, {
          ...myRating,
          'rating_avg': 3.5,
          'rating_count': 2,
          'ratings_page': page(2, 3.5),
        }),
        data: Matchers.any,
        queryParameters: {'return': 'ratings_page'},
      );

      await notifier.submitRating(const MyRating(stars: 3));

      expect(lines(), ['POST ${itineraryRatingsEndpoint(kTripId)}']);
      final shown = container.read(ratingsPageProvider(kTripId)).value!;
      expect((shown.ratingAvg, shown.ratingCount), (3.5, 2));
      expect((detail().ratingAvg, detail().ratingCount), (3.5, 2));
    });

    test('deleted from the open ratings page, the page left is adopted',
        () async {
      await load();
      final notifier = await rater();
      await ratingsPageOpen();
      adapter.onDelete(
        itineraryMyRatingEndpoint(kTripId),
        (server) => server.reply(200, page(0, null)),
        queryParameters: {'return': 'ratings_page'},
      );

      await notifier.deleteRating();

      expect(lines(), ['DELETE ${itineraryMyRatingEndpoint(kTripId)}']);
      final shown = container.read(ratingsPageProvider(kTripId)).value!;
      expect((shown.ratingAvg, shown.ratingCount), (null, 0));
      expect((detail().ratingAvg, detail().ratingCount), (null, 0));
    });

    test('with no trip loaded, nothing is fetched to put it on', () async {
      connect();
      final notifier = await rater();
      adapter.onPost(
        itineraryRatingsEndpoint(kTripId),
        (server) => server.reply(
            201, {...myRating, 'rating_avg': 3.5, 'rating_count': 2}),
        data: Matchers.any,
      );

      await notifier.submitRating(const MyRating(stars: 3));

      expect(lines(), ['POST ${itineraryRatingsEndpoint(kTripId)}']);
      expect(container.exists(itineraryDetailProvider(kTripId)), isFalse);
    });
  });
}
