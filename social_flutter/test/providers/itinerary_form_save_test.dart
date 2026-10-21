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

const _itinId = 'itin-1';
const _loadedAt = '2026-10-21T10:00:00.000000Z';
const _savedAt = '2026-10-21T10:00:05.123456Z';
const _coverUrl = '/uploads/itineraries/itin-1.jpg';
final _cover = Uint8List.fromList(List<int>.generate(64, (i) => i));

Map<String, dynamic> _summaryJson({
  String title = 'Coast walk',
  String? coverUrl,
  String updatedAt = _savedAt,
}) =>
    {
      'id': _itinId,
      'user_id': 'user-1',
      'title': title,
      'cover_image_url': coverUrl,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-21T09:00:00.000000Z',
      'updated_at': updatedAt,
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': 0,
    };

Map<String, dynamic> _detailJson({
  String title = 'Coast walk',
  String? coverUrl,
  String updatedAt = _loadedAt,
  String description = 'A walk along the coast.',
}) =>
    {
      ..._summaryJson(title: title, coverUrl: coverUrl, updatedAt: updatedAt),
      'description': description,
      'tracks': <Map<String, dynamic>>[],
      'segments': <Map<String, dynamic>>[],
      'annotations': <Map<String, dynamic>>[],
    };

/// What a trip edit answers when the app asks for the trip back.
Map<String, dynamic> _answer(Map<String, dynamic> trip) =>
    {'itinerary': trip, 'created_id': null};

/// A claim held by this device, without the network or the heartbeat.
class _HeldClaim extends EditLockNotifier {
  _HeldClaim(super.arg);

  @override
  EditSession build() {
    super.build();
    return const EditSession(token: 'lock-token');
  }
}

void main() {
  late DioAdapter adapter;
  late List<RequestOptions> sent;
  late ProviderContainer container;

  Future<ItineraryDetailNotifier> load({String? coverUrl}) async {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    adapter = DioAdapter(dio: dio);
    sent = [];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.next(options);
    }));
    adapter.onGet(itineraryEndpoint(_itinId),
        (server) => server.reply(200, _detailJson(coverUrl: coverUrl)));
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(dio)),
      editLockProvider.overrideWith2(_HeldClaim.new),
    ]);
    await container.read(itineraryDetailProvider(_itinId).future);
    sent.clear(); // the load is not the save
    return container.read(itineraryDetailProvider(_itinId).notifier);
  }

  tearDown(() => container.dispose());

  test('Given a new cover and a title, Then one request carries both and its '
      'answer is the next If-Match', () async {
    final notifier = await load();
    final loaded = container.read(itineraryDetailProvider(_itinId)).value!;
    adapter.onPatch(
      itineraryFormEndpoint(_itinId),
      (server) => server.reply(
          200,
          _answer(_detailJson(
            title: 'Coast walk, revised',
            coverUrl: _coverUrl,
            updatedAt: _savedAt,
          ))),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
      headers: {'If-Match': loaded.eTag, kEditLockHeader: 'lock-token'},
    );

    await notifier.saveForm(
      {'title': 'Coast walk, revised', 'currency': 'EUR'},
      coverBytes: _cover,
      coverFilename: 'cover.jpg',
    );

    // No /image call before it and no reload after it.
    expect(sent.map((o) => '${o.method} ${o.path}'),
        ['PATCH ${itineraryFormEndpoint(_itinId)}']);
    final saved = container.read(itineraryDetailProvider(_itinId)).value!;
    expect(saved.updatedAt, DateTime.parse(_savedAt));
    expect(saved.eTag, '"${DateTime.parse(_savedAt).toIso8601String()}"');
    expect(saved.coverImageUrl, _coverUrl);
    expect(saved.title, 'Coast walk, revised');
    expect(saved.description, 'A walk along the coast.');

    adapter.onPatch(
      itineraryEndpoint(_itinId),
      (server) => server.reply(
          200,
          _answer(_detailJson(
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
      itineraryFormEndpoint(_itinId),
      (server) => server.reply(200, _answer(_detailJson(updatedAt: _savedAt))),
      data: Matchers.any,
    );

    await notifier.saveForm({'title': 'Coast walk'}, removeCover: true);

    final saved = container.read(itineraryDetailProvider(_itinId)).value!;
    expect(saved.coverImageUrl, isNull);
    expect(saved.updatedAt, DateTime.parse(_savedAt));
  });

  test('Given a 412, Then it throws ItineraryStaleException, the loaded trip is '
      'kept as it was, and the write counts as failed', () async {
    final notifier = await load();
    final loaded = container.read(itineraryDetailProvider(_itinId)).value!;
    adapter.onPatch(
      itineraryFormEndpoint(_itinId),
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

    final after = container.read(itineraryDetailProvider(_itinId)).value!;
    expect(after.eTag, loaded.eTag);
    expect(after.title, loaded.title);
    expect(notifier.hasWritesInFlight, isFalse);
  });
}
