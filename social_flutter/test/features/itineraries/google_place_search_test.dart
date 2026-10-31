// Google's suggestions are billed per request, so the notifier asks only when
// it must: after a pause in the typing, from 3 characters, and a newer
// question drops the answer to an older one.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';

import '../../support/recording_dio.dart';

Map<String, dynamic> _answer(String name) => {
      'suggestions': [
        {'place_id': 'ChIJ$name', 'main_text': name, 'secondary_text': 'Paris'},
      ],
    };

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container(RecordingDio api) {
    final c = ProviderContainer(overrides: [
      placesRepositoryProvider.overrideWithValue(PlacesRepository(api.dio)),
    ]);
    addTearDown(c.dispose);
    // autoDispose: keep it alive for the test.
    c.listen(googlePlaceSearchProvider, (_, _) {});
    return c;
  }

  // testWidgets for its fake clock: the pause is a Timer.
  testWidgets('typing asks once, after the pause', (tester) async {
    final api = RecordingDio();
    api.adapter.onPost(kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(200, _answer('Marcel')),
        data: {'input': 'chez marcel', 'language': 'fr'});
    final c = container(api);
    final notifier = c.read(googlePlaceSearchProvider.notifier);

    notifier.typed('chez', language: 'fr');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.typed('chez marc', language: 'fr');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.typed('chez marcel', language: 'fr');
    expect(api.sent, isEmpty);

    await tester.pump(GooglePlaceSearchNotifier.typingPause);
    await tester.pumpAndSettle();

    expect(api.lines, ['POST $kGooglePlaceAutocompleteEndpoint']);
    expect(c.read(googlePlaceSearchProvider).value!.single.mainText, 'Marcel');
  });

  testWidgets('under 3 characters nothing is asked', (tester) async {
    final api = RecordingDio();
    final c = container(api);
    c.read(googlePlaceSearchProvider.notifier).typed('ch', language: 'en');
    await tester.pump(const Duration(seconds: 2));
    expect(api.sent, isEmpty);
  });

  test('the bias travels with the question', () async {
    final api = RecordingDio();
    api.adapter.onPost(kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(200, _answer('Tower')),
        data: {
          'input': 'eiffel',
          'language': 'en',
          'bias': {'lat': 48.9, 'lng': 2.3},
        });
    final c = container(api);

    await c.read(googlePlaceSearchProvider.notifier).searchNow('eiffel',
        language: 'en', bias: (lat: 48.9, lng: 2.3));

    expect(c.read(googlePlaceSearchProvider).value!.single.placeId, 'ChIJTower');
  });

  test("a question's late answer never replaces what came after it",
      () async {
    final api = RecordingDio();
    api.adapter.onPost(kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(200, _answer('Old')),
        data: {'input': 'old place', 'language': 'en'});
    final c = container(api);
    final notifier = c.read(googlePlaceSearchProvider.notifier);

    final asked = notifier.searchNow('old place', language: 'en');
    notifier.clear(); // the field was emptied while Google was answering
    await asked;

    expect(c.read(googlePlaceSearchProvider).value, isEmpty);
  });
}
