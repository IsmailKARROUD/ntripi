// The map picker searches OpenStreetMap when the search is submitted — never
// as the user types: Nominatim's policy forbids search-as-you-type, and its one
// request a second is for the whole app. A submitted search always answers:
// its places, "no places found", or why it failed. A pick collapses the list,
// and it comes back when the user is in the field again.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/core/services/location_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/presentation/map_picker_screen.dart';
import 'package:ntripi/l10n/app_localizations.dart';

class _NoLocation extends LocationService {
  @override
  Future<LocationOutcome> getCurrentLatLng() async => const LocationUnavailable();
}

/// Records every Nominatim query and answers it from [answer].
class _RecordingGeocoding extends GeocodingService {
  _RecordingGeocoding(this.answer);

  final FutureOr<List<PlaceSuggestion>> Function(String query) answer;
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

  @override
  Future<PlaceSuggestion?> reverseGeocode(
    double lat,
    double lng, {
    String? languageCode,
  }) async =>
      null;
}

const _louvre = PlaceSuggestion(
    displayName: 'Louvre', address: 'Rue de Rivoli, Paris', lat: 48.86, lng: 2.34);

/// What Dio throws when Nominatim cannot be reached.
DioException _offline() => DioException(
    requestOptions: RequestOptions(path: '/search'),
    type: DioExceptionType.connectionError);

Future<_RecordingGeocoding> _pump(
  WidgetTester tester, {
  FutureOr<List<PlaceSuggestion>> Function(String query)? answer,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final geocoding = _RecordingGeocoding(answer ?? (_) => const [_louvre]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      geocodingServiceProvider.overrideWithValue(geocoding),
      locationServiceProvider.overrideWithValue(_NoLocation()),
    ],
    child: MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MapPickerScreen(initialLat: 48.85, initialLng: 2.35),
    ),
  ));
  await tester.pump();
  return geocoding;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MapPickerScreen)))!;

Finder get _field => find.byKey(MapPickerScreen.searchFieldKey);

/// The line answering a submitted search, holding [text].
Finder _notice(String text) => find.descendant(
    of: find.byKey(MapPickerScreen.searchNoticeKey), matching: find.text(text));

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

Finder get _list => find.byKey(MapPickerScreen.suggestionsKey);

/// Searches the Louvre and picks it from the list.
Future<void> _pickLouvre(WidgetTester tester) async {
  await _submit(tester, 'louvre');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.descendant(of: _list, matching: find.text('Louvre')));
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Given text typed in the picker, When nothing is submitted, Then '
      'OpenStreetMap is never asked', (tester) async {
    final geocoding = await _pump(tester);

    await tester.enterText(_field, 'louvre');
    await tester.pump(const Duration(seconds: 3));

    expect(geocoding.queries, isEmpty);
  });

  testWidgets(
      "Given text typed in the picker, When the keyboard's Search is pressed, "
      'Then OpenStreetMap is asked once and the result shows', (tester) async {
    final geocoding = await _pump(tester);

    await _submit(tester, 'louvre');
    await tester.pump(const Duration(milliseconds: 100));

    expect(geocoding.queries, ['louvre']);
    expect(find.text('Louvre'), findsOneWidget);
  });

  testWidgets(
      'Given text typed in the picker, When the search arrow is tapped, Then '
      'OpenStreetMap is asked once', (tester) async {
    final geocoding = await _pump(tester);
    final l10n = _l10n(tester);

    await tester.enterText(_field, 'louvre');
    await tester.pump();
    await tester.tap(find.byTooltip(l10n.placeSearchButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(geocoding.queries, ['louvre']);
  });

  testWidgets(
      'Given OpenStreetMap cannot be reached, When a search is submitted, Then '
      'the picker says so instead of its pin instructions', (tester) async {
    final geocoding = await _pump(tester, answer: (_) => throw _offline());
    final l10n = _l10n(tester);

    await _submit(tester, 'louvre');
    await tester.pump();

    expect(geocoding.queries, ['louvre']);
    expect(_notice(l10n.errorNoInternet), findsOneWidget);
    expect(find.text(l10n.mapTapToPlacePin), findsNothing);
    expect(find.text(l10n.mapTapToMovePin), findsNothing);
  });

  testWidgets(
      'Given a failed search, When the user types something else, Then the '
      'failure no longer shows', (tester) async {
    await _pump(tester, answer: (_) => throw _offline());
    final l10n = _l10n(tester);
    await _submit(tester, 'louvre');
    await tester.pump();
    expect(_notice(l10n.errorNoInternet), findsOneWidget);

    await tester.enterText(_field, 'louvre museum');
    await tester.pump();

    expect(find.text(l10n.errorNoInternet), findsNothing);
  });

  testWidgets(
      'Given nothing near matches, When a search is submitted, Then it widens '
      'one request a second and then says no places were found',
      (tester) async {
    final geocoding = await _pump(tester, answer: (_) => const []);
    final l10n = _l10n(tester);

    await _submit(tester, 'nowhere');
    await tester.pump(const Duration(milliseconds: 900));
    expect(geocoding.queries, hasLength(1),
        reason: "Nominatim's policy is one request a second");

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    // The view, four times it, sixteen times it, then anywhere.
    expect(geocoding.queries, hasLength(4));
    expect(_notice(l10n.mapSearchNoResults), findsOneWidget);
  });

  testWidgets(
      'Given results on screen, When Clear is tapped, Then they go and the '
      'field is empty', (tester) async {
    await _pump(tester);
    final l10n = _l10n(tester);
    await _submit(tester, 'louvre');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Louvre'), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.mapLinkClear));
    await tester.pump();

    expect(find.text('Louvre'), findsNothing);
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
  });

  testWidgets(
      'Given a picked result, When the field is tapped, Then the list comes '
      'back without a new search', (tester) async {
    final geocoding = await _pump(tester);
    await _pickLouvre(tester);
    expect(_list, findsNothing);

    await tester.tap(_field);
    await tester.pump();

    expect(_list, findsOneWidget);
    expect(geocoding.queries, ['louvre']);
  });

  testWidgets(
      'Given a picked result, When a screen reader activates the field, Then '
      'the list comes back', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await _pickLouvre(tester);
    expect(_list, findsNothing);

    // Focuses the field without a tap: onTap is never called.
    tester.semantics.tap(find.semantics.byFlag(SemanticsFlag.isTextField));
    await tester.pump();

    expect(_list, findsOneWidget);
    semantics.dispose();
  });
}
