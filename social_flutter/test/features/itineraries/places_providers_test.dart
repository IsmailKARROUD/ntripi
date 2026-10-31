// The Google places data layer: what the config says, what a search sends,
// and how a refusal reaches the state.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';

import '../../support/recording_dio.dart';

ProviderContainer _container(
  RecordingDio api, {
  bool signedIn = true,
  Stream<bool>? online,
}) {
  final c = ProviderContainer(overrides: [
    placesRepositoryProvider.overrideWithValue(PlacesRepository(api.dio)),
    hasSessionProvider.overrideWith((ref) async => signedIn),
    isOnlineProvider.overrideWith((ref) => online ?? Stream.value(true)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  // A failed config read listens for the app's return to the foreground.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('placesConfigProvider', () {
    test('Given no session, When read, Then Google is off and nothing is asked',
        () async {
      final api = RecordingDio();
      final c = _container(api, signedIn: false);

      final config = await c.read(placesConfigProvider.future);

      expect([config.googleSearch, config.googleMaps], [false, false]);
      expect(api.sent, isEmpty);
    });

    test('Given a session, When the server answers, Then its switches are used',
        () async {
      final api = RecordingDio();
      api.adapter.onGet(kPlacesConfigEndpoint,
          (s) => s.reply(200, {'google_search': true, 'google_maps': false}));
      final c = _container(api);

      final config = await c.read(placesConfigProvider.future);

      expect([config.googleSearch, config.googleMaps], [true, false]);
    });

    test('Given the server fails, When read, Then Google is off for now',
        () async {
      final api = RecordingDio();
      api.adapter.onGet(kPlacesConfigEndpoint, (s) => s.reply(500, {}));
      final c = _container(api);

      final config = await c.read(placesConfigProvider.future);

      expect([config.googleSearch, config.googleMaps], [false, false]);
    });

    test(
        'Given a failed read, When the network comes back, Then the config is '
        'asked again', () async {
      final api = RecordingDio();
      api.adapter.onGet(kPlacesConfigEndpoint, (s) => s.reply(500, {}));
      final network = StreamController<bool>();
      addTearDown(network.close);
      final c = _container(api, online: network.stream);
      c.listen(placesConfigProvider, (_, _) {});
      network.add(false);
      await c.read(placesConfigProvider.future);
      expect(api.lines, ['GET $kPlacesConfigEndpoint']);

      api.adapter.onGet(kPlacesConfigEndpoint,
          (s) => s.reply(200, {'google_search': true, 'google_maps': true}));
      network.add(true);
      await pumpEventQueue();
      final config = await c.read(placesConfigProvider.future);

      expect(api.lines.length, 2);
      expect([config.googleSearch, config.googleMaps], [true, true]);
    });

    test('Given an answer missing a switch, When parsed, Then that switch is off',
        () {
      final config = PlacesConfig.fromJson({'google_maps': true});
      expect([config.googleSearch, config.googleMaps], [false, true]);
    });
  });

  group('PlacesRepository.autocomplete', () {
    test('Given no bias, When asked, Then the body carries no location',
        () async {
      final api = RecordingDio();
      api.adapter.onPost(kGooglePlaceAutocompleteEndpoint,
          (s) => s.reply(200, {'suggestions': []}),
          data: {'input': 'louvre', 'language': 'en'});

      final suggestions = await PlacesRepository(api.dio)
          .autocomplete(input: 'louvre', language: 'en');

      expect(suggestions, isEmpty);
      expect((api.sent.single.data as Map).containsKey('bias'), isFalse);
    });

    test('Given a suggestion without a secondary line, When parsed, Then it '
        'still reads', () async {
      final api = RecordingDio();
      api.adapter.onPost(
        kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(200, {
          'suggestions': [
            {'place_id': 'ChIJx', 'main_text': 'Louvre'},
          ],
        }),
        data: Matchers.any,
      );

      final [only] = await PlacesRepository(api.dio)
          .autocomplete(input: 'louvre', language: 'en');

      expect([only.placeId, only.mainText, only.secondaryText],
          ['ChIJx', 'Louvre', null]);
    });
  });

  group('GooglePlaceSearchNotifier', () {
    ProviderContainer searching(RecordingDio api) {
      final c = _container(api);
      c.listen(googlePlaceSearchProvider, (_, _) {});
      return c;
    }

    test(
        'Given the hourly budget is spent, When asked, Then the state is the '
        'refusal, not an empty list', () async {
      final api = RecordingDio();
      api.adapter.onPost(
        kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(429, {
          'code': 'place_search_rate_limited',
          'detail': 'Too many Google place searches — try again later.',
        }),
        data: Matchers.any,
      );
      final c = searching(api);

      await c
          .read(googlePlaceSearchProvider.notifier)
          .searchNow('chez marcel', language: 'en');

      final state = c.read(googlePlaceSearchProvider);
      expect(state.hasError, isTrue);
      expect((state.error! as DioException).response?.statusCode, 429);
    });

    test('Given fewer than 3 characters, When asked now, Then nothing is sent',
        () async {
      final api = RecordingDio();
      final c = searching(api);

      await c
          .read(googlePlaceSearchProvider.notifier)
          .searchNow('  ab  ', language: 'en');

      expect(api.sent, isEmpty);
      expect(c.read(googlePlaceSearchProvider).value, isEmpty);
    });
  });
}
