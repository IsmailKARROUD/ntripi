// test/providers/itinerary_form_save_test.dart — ItineraryDetailNotifier.saveForm
// against the real repository on a mocked Dio.
//
// The form's save is one request, and the trip it answers with is adopted in
// place: the next write must carry the new ETag without a reload. The old
// two-request save read the ETag once, before the cover write moved it, and its
// PATCH was refused.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';

import '../support/held_claim.dart';
import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _coverUrl = '/uploads/itineraries/itin-1.jpg';
const _description = 'A walk along the coast.';
final _cover = Uint8List.fromList(List<int>.generate(64, (i) => i));

void main() {
  late DioAdapter adapter;
  late List<RequestOptions> sent;
  late ProviderContainer container;

  Future<ItineraryDetailNotifier> load({String? coverUrl}) async {
    final api = RecordingDio();
    adapter = api.adapter;
    sent = api.sent;
    adapter.onGet(itineraryEndpoint(kTripId),
        (server) => server.reply(
            200, tripJson(coverUrl: coverUrl, description: _description)));
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider
          .overrideWithValue(ItineraryRepository(api.dio)),
      editLockProvider.overrideWith2(HeldClaim.new),
    ]);
    await container.read(itineraryDetailProvider(kTripId).future);
    sent.clear(); // the load is not the save
    return container.read(itineraryDetailProvider(kTripId).notifier);
  }

  tearDown(() => container.dispose());

  test('Given a new cover and a title, Then one request carries both and its '
      'answer is the next If-Match', () async {
    final notifier = await load();
    final loaded = container.read(itineraryDetailProvider(kTripId)).value!;
    adapter.onPatch(
      itineraryFormEndpoint(kTripId),
      (server) => server.reply(
          200,
          tripAnswer(tripJson(
            title: 'Coast walk, revised',
            coverUrl: _coverUrl,
            updatedAt: kSavedAt,
            description: _description,
          ))),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
      headers: {'If-Match': loaded.eTag, kEditLockHeader: kHeldClaimToken},
    );

    await notifier.saveForm(
      {'title': 'Coast walk, revised', 'currency': 'EUR'},
      coverBytes: _cover,
      coverFilename: 'cover.jpg',
    );

    // No /image call before it and no reload after it.
    expect(sent.map((o) => '${o.method} ${o.path}'),
        ['PATCH ${itineraryFormEndpoint(kTripId)}']);
    final saved = container.read(itineraryDetailProvider(kTripId)).value!;
    expect(saved.updatedAt, DateTime.parse(kSavedAt));
    expect(saved.eTag, '"${DateTime.parse(kSavedAt).toIso8601String()}"');
    expect(saved.coverImageUrl, _coverUrl);
    expect(saved.title, 'Coast walk, revised');
    expect(saved.description, _description);

    adapter.onPatch(
      itineraryEndpoint(kTripId),
      (server) => server.reply(
          200,
          tripAnswer(tripJson(
            description: 'Shorter.',
            updatedAt: '2026-10-21T10:01:00.000000Z',
          ))),
      data: Matchers.any,
      headers: {'If-Match': saved.eTag},
    );
    await notifier.updateHeader({'description': 'Shorter.'});
    expect(sent.last.headers['If-Match'], saved.eTag);
  });

  test('Given a removed cover, Then the cover is cleared in state', () async {
    final notifier = await load(coverUrl: _coverUrl);
    adapter.onPatch(
      itineraryFormEndpoint(kTripId),
      (server) => server.reply(200,
          tripAnswer(tripJson(description: _description, updatedAt: kSavedAt))),
      data: Matchers.any,
    );

    await notifier.saveForm({'title': 'Coast walk'}, removeCover: true);

    final saved = container.read(itineraryDetailProvider(kTripId)).value!;
    expect(saved.coverImageUrl, isNull);
    expect(saved.updatedAt, DateTime.parse(kSavedAt));
  });

  test('Given a 412, Then it throws ItineraryStaleException, the loaded trip is '
      'kept as it was, and the write counts as failed', () async {
    final notifier = await load();
    final loaded = container.read(itineraryDetailProvider(kTripId)).value!;
    adapter.onPatch(
      itineraryFormEndpoint(kTripId),
      (server) => server.reply(412, {
        'detail': 'itinerary modified, please reload',
        'code': 'itinerary_stale',
      }),
      data: Matchers.any,
    );

    await expectLater(
      notifier.saveForm({'title': 'Too late'}, coverBytes: _cover),
      throwsA(isA<ItineraryStaleException>()),
    );

    final after = container.read(itineraryDetailProvider(kTripId)).value!;
    expect(after.eTag, loaded.eTag);
    expect(after.title, loaded.title);
    expect(notifier.hasWritesInFlight, isFalse);
  });
}
