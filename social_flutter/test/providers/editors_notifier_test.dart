// test/providers/editors_notifier_test.dart — granting and revoking edit rights
// download nothing.
//
// A grant or a revoke leaves the trip's stamp and everything its owner sees as
// it was, so neither reloads the trip. An editor who leaves changes only what
// their own copy says about them — can_edit, and the trip's row in Shared with
// me — and both change in place. Run against the real repository on a mocked
// Dio, so "no GET" is an exact assertion.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';

import '../support/recording_dio.dart';
import '../support/trip_json.dart';

Map<String, dynamic> _editorJson(String userId) => {
      'user_id': userId,
      'username': 'editor-$userId',
      'display_name': null,
      'avatar_url': null,
      'created_at': '2026-10-21T09:30:00.000000Z',
    };

void main() {
  late RecordingDio api;
  late ProviderContainer container;

  /// The trip, its Shared row and its editors as their screens loaded them,
  /// then a clean request log.
  Future<EditorsNotifier> load() async {
    api = RecordingDio();
    api.adapter
      ..onGet(itineraryEndpoint(kTripId),
          (server) => server.reply(200, tripJson()))
      ..onGet(kSharedWithMeEndpoint,
          (server) => server.reply(200, [sharedRowJson(summaryJson())]))
      ..onGet(itineraryEditorsEndpoint(kTripId),
          (server) => server.reply(200, [_editorJson('ed-1')]));
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider
          .overrideWithValue(ItineraryRepository(api.dio)),
    ]);
    await container.read(itineraryDetailProvider(kTripId).future);
    await container.read(sharedWithMeProvider.future);
    await container.read(editorsProvider(kTripId).future);
    api.sent.clear();
    return container.read(editorsProvider(kTripId).notifier);
  }

  List<String> editorIds() => [
        for (final editor in container.read(editorsProvider(kTripId)).value!)
          editor.userId,
      ];

  tearDown(() => container.dispose());

  test('a grant downloads nothing: the trip is as it was', () async {
    final editors = await load();
    api.adapter.onPost(itineraryEditorsEndpoint(kTripId),
        (server) => server.reply(201, _editorJson('ed-2')),
        data: Matchers.any);

    await editors.addEditor('ed-2');

    expect(api.lines, ['POST ${itineraryEditorsEndpoint(kTripId)}']);
    expect(editorIds(), ['ed-1', 'ed-2']);
  });

  test("a revoke downloads nothing, and leaves the owner's trip as it was",
      () async {
    final editors = await load();
    api.adapter.onDelete(itineraryEditorEndpoint(kTripId, 'ed-1'),
        (server) => server.reply(204, null));

    await editors.removeEditor('ed-1');

    expect(api.lines, ['DELETE ${itineraryEditorEndpoint(kTripId, 'ed-1')}']);
    expect(editorIds(), isEmpty);
    expect(container.read(itineraryDetailProvider(kTripId)).value!.canEdit,
        isTrue);
    expect(container.read(sharedWithMeProvider).value, hasLength(1));
  });

  test('leaving ends my edit rights and my Shared row in place', () async {
    final editors = await load();
    api.adapter.onDelete(itineraryEditorEndpoint(kTripId, 'ed-1'),
        (server) => server.reply(204, null));

    await editors.leave('ed-1');

    expect(api.lines, ['DELETE ${itineraryEditorEndpoint(kTripId, 'ed-1')}']);
    expect(container.read(itineraryDetailProvider(kTripId)).value!.canEdit,
        isFalse);
    expect(container.read(sharedWithMeProvider).value, isEmpty);
    expect(editorIds(), isEmpty);
  });
}
