// PlaceSearchBox on its own: the states between a submitted search and a pick
// — waiting, OpenStreetMap failing, Google refusing, Google finding nothing —
// the way back from Google to OpenStreetMap, and what a pick leaves: the list
// folded away, back when the user is in the field again, at no new request.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/place_search_box.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';

import '../support/recording_dio.dart';

/// Answers OSM queries from [answer]: a list, or a Future the test holds.
class _Geocoding extends GeocodingService {
  _Geocoding(this.answer);

  FutureOr<List<PlaceSuggestion>> Function(String query) answer;
  final List<String> queries = [];

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    String? languageCode,
    LatLng? near,
    LatLng? boxSw,
    LatLng? boxNe,
    bool bounded = false,
  }) async {
    queries.add(query);
    return answer(query);
  }
}

const _louvre = PlaceSuggestion(
  displayName: 'Louvre',
  address: 'Rue de Rivoli, Paris',
  lat: 48.86,
  lng: 2.34,
);

/// What Dio throws when Nominatim cannot be reached.
DioException _offline() => DioException(
    requestOptions: RequestOptions(path: '/search'),
    type: DioExceptionType.connectionError);

class _Box {
  final RecordingDio api;
  final _Geocoding geocoding;
  final TextEditingController controller;
  final AppLocalizations l10n;
  final List<String> osmPicks;
  final List<String> googlePicks;

  _Box(this.api, this.geocoding, this.controller, this.l10n, this.osmPicks,
      this.googlePicks);

  /// Google answers every question with Chez Marcel.
  void googleFinds() => api.adapter.onPost(
        kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(200, {
          'suggestions': [
            {'place_id': 'ChIJx', 'main_text': 'Chez Marcel', 'secondary_text': 'Paris'},
          ],
        }),
        data: Matchers.any,
      );

  int get googleAsked => api.sent.length;
}

Future<_Box> _pump(
  WidgetTester tester, {
  required _Geocoding geocoding,
  bool googleFallback = true,
  bool googleSearch = true,
  double textScale = 1,
  List<String>? handedLinks,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = RecordingDio();
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  final osmPicks = <String>[];
  final picks = <String>[];

  await tester.pumpWidget(ProviderScope(
    overrides: [
      geocodingServiceProvider.overrideWithValue(geocoding),
      placesRepositoryProvider.overrideWithValue(PlacesRepository(api.dio)),
      placesConfigProvider.overrideWith((ref) async =>
          PlacesConfig(googleSearch: googleSearch, googleMaps: false)),
    ],
    child: MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(400, 900),
            textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PlaceSearchBox(
              controller: controller,
              googleFallback: googleFallback,
              language: 'en',
              bias: () => null,
              onOsmPick: (suggestion) => osmPicks.add(suggestion.displayName),
              onGooglePick: (suggestion, text) =>
                  picks.add('${suggestion.placeId} $text'),
              onMapLink: handedLinks?.add,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(tester.element(find.byType(PlaceSearchBox)))!;
  return _Box(api, geocoding, controller, l10n, osmPicks, picks);
}

/// Searches [text] until Google's list shows, and picks Chez Marcel from it.
Future<void> _pickOnGoogle(WidgetTester tester, _Box box, String text) async {
  box.googleFinds();
  await _submit(tester, text);
  await tester.pumpAndSettle();
  expect(find.byKey(PlaceSearchBox.googleListKey), findsOneWidget);
  await tester.tap(find.text('Chez Marcel'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(PlaceSearchBox.fieldKey), text);
  await tester.pump();
  await tester.tap(find.byKey(PlaceSearchBox.submitKey));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
      'Given a submitted search, When OpenStreetMap has not answered, Then a '
      'progress bar shows, and the results replace it', (tester) async {
    final answer = Completer<List<PlaceSuggestion>>();
    await _pump(tester, geocoding: _Geocoding((_) => answer.future));

    await _submit(tester, 'louvre');
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(PlaceSearchBox.osmListKey), findsNothing);

    answer.complete([_louvre]);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(PlaceSearchBox.osmListKey), findsOneWidget);
  });

  testWidgets(
      'Given OpenStreetMap cannot be reached, When a search is submitted, Then '
      'the box says so and still offers Google, without asking it',
      (tester) async {
    final box = await _pump(tester, geocoding: _Geocoding((_) => throw _offline()));

    await _submit(tester, 'louvre');
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byKey(PlaceSearchBox.noticeKey),
            matching: find.text(box.l10n.errorNoInternet)),
        findsOneWidget);
    expect(find.byKey(PlaceSearchBox.askGoogleKey), findsOneWidget);
    // Only an empty answer asks Google: an outage must not spend paid requests.
    expect(box.api.sent, isEmpty);
  });

  testWidgets(
      'Given OpenStreetMap cannot be reached in the Coordinates segment, When '
      'a search is submitted, Then the box says so and offers no Google',
      (tester) async {
    final box = await _pump(tester,
        googleFallback: false, geocoding: _Geocoding((_) => throw _offline()));

    await _submit(tester, 'louvre');
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byKey(PlaceSearchBox.noticeKey),
            matching: find.text(box.l10n.errorNoInternet)),
        findsOneWidget);
    expect(find.byKey(PlaceSearchBox.askGoogleKey), findsNothing);
  });

  testWidgets(
      "Given this hour's Google searches are spent, When Google is asked, "
      'Then the box says so in the reader’s language', (tester) async {
    final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
    box.api.adapter.onPost(
      kGooglePlaceAutocompleteEndpoint,
      (s) => s.reply(429, {
        'code': 'place_search_rate_limited',
        'detail': 'Too many Google place searches — try again later.',
      }),
      data: Matchers.any,
    );

    await _submit(tester, 'chez marcel');
    await tester.pumpAndSettle();

    expect(find.text(box.l10n.apiErrorPlaceSearchRateLimited), findsOneWidget);
  });

  testWidgets(
      'Given Google finds nothing either, When answered, Then the box says '
      'no places were found', (tester) async {
    final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
    box.api.adapter.onPost(kGooglePlaceAutocompleteEndpoint,
        (s) => s.reply(200, {'suggestions': []}),
        data: Matchers.any);

    await _submit(tester, 'nowhere at all');
    await tester.pumpAndSettle();

    expect(find.text(box.l10n.mapSearchNoResults), findsOneWidget);
  });

  testWidgets(
      'Given the box is on Google, When the field is cleared, Then it is back '
      'on OpenStreetMap and typing asks Google nothing', (tester) async {
    final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
    box.api.adapter.onPost(
      kGooglePlaceAutocompleteEndpoint,
      (s) => s.reply(200, {
        'suggestions': [
          {'place_id': 'ChIJx', 'main_text': 'Chez Marcel'},
        ],
      }),
      data: Matchers.any,
    );
    await _submit(tester, 'chez marcel');
    await tester.pumpAndSettle();
    expect(find.byKey(PlaceSearchBox.googleListKey), findsOneWidget);

    await tester.tap(find.byKey(PlaceSearchBox.clearKey));
    await tester.pumpAndSettle();
    final asked = box.api.sent.length;
    await tester.enterText(find.byKey(PlaceSearchBox.fieldKey), 'louvre museum');
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(PlaceSearchBox.googleListKey), findsNothing);
    expect(box.api.sent.length, asked);
  });

  testWidgets(
      'Given Google search is switched off, When OpenStreetMap finds nothing, '
      'Then the box says so and offers no Google', (tester) async {
    final box = await _pump(tester,
        googleSearch: false, geocoding: _Geocoding((_) => const []));

    await _submit(tester, 'chez marcel');
    await tester.pumpAndSettle();

    expect(find.text(box.l10n.placeSearchNoResults), findsOneWidget);
    expect(find.byKey(PlaceSearchBox.askGoogleKey), findsNothing);
    expect(box.api.sent, isEmpty);
  });

  testWidgets(
      'Given a Google suggestion, When picked, Then the pick carries its ID '
      'and the text the user typed', (tester) async {
    final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
    box.api.adapter.onPost(
      kGooglePlaceAutocompleteEndpoint,
      (s) => s.reply(200, {
        'suggestions': [
          {'place_id': 'ChIJx', 'main_text': 'Chez Marcel', 'secondary_text': 'Paris'},
        ],
      }),
      data: Matchers.any,
    );
    await _submit(tester, 'chez marcel');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chez Marcel'));

    expect(box.googlePicks, ['ChIJx chez marcel']);
  });

  testWidgets(
      'Given the largest text size, When OSM results and the Google row show, '
      'Then nothing overflows', (tester) async {
    final box = await _pump(tester,
        textScale: 2, geocoding: _Geocoding((_) => [_louvre]));

    await _submit(tester, 'louvre');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(box.l10n.searchOnGoogleMaps), findsOneWidget);
  });

  group('after a pick', () {
    testWidgets(
        'Given Google suggestions, When one is picked, Then the list folds '
        'away and the field keeps the words', (tester) async {
      final box = await _pump(tester, geocoding: _Geocoding((_) => const []));

      await _pickOnGoogle(tester, box, 'chez marcel');

      expect(box.googlePicks, ['ChIJx chez marcel']);
      expect(find.byKey(PlaceSearchBox.googleListKey), findsNothing);
      expect(box.controller.text, 'chez marcel');
    });

    testWidgets(
        'Given a pick folded the Google list, When the field is tapped, Then '
        'the same suggestions come back and Google is not asked again',
        (tester) async {
      final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
      await _pickOnGoogle(tester, box, 'chez marcel');
      final asked = box.googleAsked;

      await tester.tap(find.byKey(PlaceSearchBox.fieldKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PlaceSearchBox.googleListKey), findsOneWidget);
      expect(box.googleAsked, asked);
    });

    testWidgets(
        'Given a pick folded the list, When a screen reader activates the '
        'field, Then the list comes back', (tester) async {
      final semantics = tester.ensureSemantics();
      final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
      await _pickOnGoogle(tester, box, 'chez marcel');

      // Focuses the field without a tap: onTap is never called.
      tester.semantics.tap(find.semantics.byFlag(SemanticsFlag.isTextField));
      await tester.pumpAndSettle();

      expect(find.byKey(PlaceSearchBox.googleListKey), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
        'Given a pick folded the Google list, When the user types more, Then '
        'Google answers the new words', (tester) async {
      final box = await _pump(tester, geocoding: _Geocoding((_) => const []));
      await _pickOnGoogle(tester, box, 'chez marcel');
      final asked = box.googleAsked;

      await tester.enterText(
          find.byKey(PlaceSearchBox.fieldKey), 'chez marcel montmartre');
      await tester.pump(GooglePlaceSearchNotifier.typingPause);
      await tester.pumpAndSettle();

      // The field still holds Google's words, so the box is still on Google.
      expect(box.googleAsked, asked + 1);
      expect(box.geocoding.queries, ['chez marcel']);
      expect(find.byKey(PlaceSearchBox.googleListKey), findsOneWidget);
    });

    testWidgets(
        'Given OpenStreetMap results, When one is picked, Then the list folds '
        'away, and a tap on the field brings it back without a new search',
        (tester) async {
      final box = await _pump(tester, geocoding: _Geocoding((_) => [_louvre]));
      await _submit(tester, 'louvre');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Louvre'));
      await tester.pumpAndSettle();
      expect(box.osmPicks, ['Louvre']);
      expect(find.byKey(PlaceSearchBox.osmListKey), findsNothing);
      expect(box.controller.text, 'louvre');

      await tester.tap(find.byKey(PlaceSearchBox.fieldKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PlaceSearchBox.osmListKey), findsOneWidget);
      expect(box.geocoding.queries, ['louvre']);
    });
  });

  group('a link in the search (no search text may hold one)', () {
    testWidgets(
        'Given a Google Maps link pasted in the search, When submitted, Then '
        "nothing is searched and it is offered as the stop's own link",
        (tester) async {
      final geocoding = _Geocoding((_) => [_louvre]);
      final handed = <String>[];
      final box = await _pump(tester, geocoding: geocoding, handedLinks: handed);
      const link = 'https://maps.app.goo.gl/abc123';

      await _submit(tester, link);
      await tester.pumpAndSettle();
      expect(geocoding.queries, isEmpty);
      expect(box.googleAsked, 0);

      await tester.tap(find.byKey(PlaceSearchBox.useAsMapLinkKey));
      await tester.pumpAndSettle();
      expect(handed, [link]);
      expect(box.controller.text, isEmpty);
    });

    testWidgets(
        'Given any other link, When submitted, Then nothing is searched and '
        'the link is named as the thing to remove', (tester) async {
      final geocoding = _Geocoding((_) => [_louvre]);
      final box = await _pump(tester, geocoding: geocoding, handedLinks: []);

      await _submit(tester, 'cafe near booking.com');
      await tester.pumpAndSettle();

      expect(geocoding.queries, isEmpty);
      expect(find.byKey(PlaceSearchBox.useAsMapLinkKey), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(PlaceSearchBox.linkNoticeKey),
              matching: find.text(box.l10n.textRuleNoLinks('booking.com'))),
          findsOneWidget);
    });
  });

  group('a search past its cap (the server takes 200 characters)', () {
    testWidgets(
        'Given 201 characters, When submitted, Then neither OSM nor Google is '
        'asked and the cap is named; back at 200, the search runs',
        (tester) async {
      final geocoding = _Geocoding((_) => [_louvre]);
      final box = await _pump(tester, geocoding: geocoding);
      box.googleFinds();

      await _submit(tester, 'a' * 201);
      await tester.pumpAndSettle();
      expect(geocoding.queries, isEmpty);
      expect(box.googleAsked, 0);
      expect(
          find.descendant(
              of: find.byKey(PlaceSearchBox.tooLongKey),
              matching: find.text(box.l10n.textRuleTooLong(200))),
          findsOneWidget);
      expect(box.controller.text.length, 201, reason: 'never cut');

      await _submit(tester, 'a' * 200);
      await tester.pumpAndSettle();
      expect(geocoding.queries, ['a' * 200]);
      expect(find.byKey(PlaceSearchBox.tooLongKey), findsNothing);
    });

    testWidgets(
        'Given a long Google Maps link, Then it is still offered as the stop\'s '
        'link — the link field takes 500 characters', (tester) async {
      final handed = <String>[];
      await _pump(tester,
          geocoding: _Geocoding((_) => [_louvre]), handedLinks: handed);
      final link = 'https://www.google.com/maps/place/Somewhere/@48.8,2.3,17z/'
          'data=${'!3m1' * 50}';
      expect(link.length, greaterThan(200));

      await _submit(tester, link);
      await tester.pumpAndSettle();
      expect(find.byKey(PlaceSearchBox.tooLongKey), findsNothing);
      await tester.tap(find.byKey(PlaceSearchBox.useAsMapLinkKey));
      await tester.pumpAndSettle();
      expect(handed, [link]);
    });
  });
}
