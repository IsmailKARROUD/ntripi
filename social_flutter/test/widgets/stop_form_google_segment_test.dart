// The stop form's place search: OpenStreetMap first, on submit; Google Places
// as the Google Maps segment's fallback; a pasted link never fetched.
//
// Pinned through what actually leaves the form: every request the API Dio
// sends (RecordingDio), every Nominatim query (a recording geocoder), every
// link fetch (a recording preview service — there must be none), and the body
// of the save.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/core/services/location_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/data/link_preview_service.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/presentation/stop_form_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/place_search_box.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/held_claim.dart';
import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _placeId = 'ChIJLU7jZClu5kcR4PcOOO6p3I0';
// Google's display text: shown to choose from, never stored or sent back.
const _googleName = 'SENTINEL Chez Marcel (Google)';

class _FakeMyProfile extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-1',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

class _NoLocation extends LocationService {
  @override
  Future<LocationOutcome> getCurrentLatLng() async => const LocationUnavailable();
}

/// Records every Nominatim query and answers [results].
class _RecordingGeocoding extends GeocodingService {
  _RecordingGeocoding([this.results = const []]);

  final List<PlaceSuggestion> results;
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
    return results;
  }
}

/// The stop page's link fetcher. The form must never reach it.
class _RecordingPreviews extends LinkPreviewService {
  final List<String> fetched = [];

  @override
  Future<LinkPreview?> fetch(String url) async {
    fetched.add(url);
    return null;
  }
}

class _Harness {
  final RecordingDio api;
  final _RecordingGeocoding geocoding;
  final _RecordingPreviews previews;
  final AppLocalizations l10n;

  _Harness(this.api, this.geocoding, this.previews, this.l10n);

  /// The stop body the save sent: a create's POST or an edit's PATCH.
  Map<String, dynamic> get savedStop => api.sent
      .lastWhere((o) =>
          (o.method == 'POST' && o.path == itineraryStopsEndpoint(kTripId)) ||
          (o.method == 'PATCH' && o.path.startsWith('${itineraryStopsEndpoint(kTripId)}/')))
      .data as Map<String, dynamic>;
}

/// A stop placed by a Google pick, as the server answers it.
Map<String, dynamic> _googleStopJson(String id,
        {String name = 'Lunch', bool missing = false}) =>
    {
      ...stopJson(id, placeName: name),
      'place_source': 'google',
      'google_place_id': _placeId,
      'google_place_query': 'chez marcel',
      'google_place_missing': missing,
    };

Future<_Harness> _pumpForm(
  WidgetTester tester, {
  List<PlaceSuggestion> osmResults = const [],
  // Edit mode: the stop the form opens, already in the trip.
  Map<String, dynamic>? editing,
  // Other stops already in the trip.
  List<Map<String, dynamic>> others = const [],
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = RecordingDio();
  final trip = tripJson(tracks: [
    if (editing != null || others.isNotEmpty)
      trackJson('t1', [if (editing != null) editing, ...others]),
  ]);
  api.adapter
    ..onGet(itineraryEndpoint(kTripId), (s) => s.reply(200, trip))
    ..onPost(
      kGooglePlaceAutocompleteEndpoint,
      (s) => s.reply(200, {
        'suggestions': [
          {
            'place_id': _placeId,
            'main_text': _googleName,
            'secondary_text': 'Montmartre, Paris',
          },
        ],
      }),
      data: Matchers.any,
    )
    ..onPost(
      itineraryStopsEndpoint(kTripId),
      (s) => s.reply(201,
          tripAnswer(tripJson(tracks: [trackJson('t1', [stopJson('new')])]),
              createdId: 'new')),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
    );
  if (editing != null) {
    api.adapter.onPatch(
      itineraryStopEndpoint(kTripId, editing['id'] as String),
      (s) => s.reply(200, tripAnswer(trip)),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
    );
  }
  final geocoding = _RecordingGeocoding(osmResults);
  final previews = _RecordingPreviews();

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: SizedBox())),
    GoRoute(
      path: '/itineraries/:id/stops/new',
      builder: (_, state) =>
          StopFormScreen(itineraryId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/itineraries/:id/stops/:stopId/edit',
      builder: (_, state) => StopFormScreen(
        itineraryId: state.pathParameters['id']!,
        stopId: state.pathParameters['stopId']!,
      ),
    ),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(api.dio)),
      placesRepositoryProvider.overrideWithValue(PlacesRepository(api.dio)),
      // Search on; maps off, so no WebView is built under test.
      placesConfigProvider.overrideWith((ref) async =>
          const PlacesConfig(googleSearch: true, googleMaps: false)),
      editLockProvider.overrideWith2(HeldClaim.new),
      myProfileProvider.overrideWith(_FakeMyProfile.new),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      locationServiceProvider.overrideWithValue(_NoLocation()),
      geocodingServiceProvider.overrideWithValue(geocoding),
      linkPreviewServiceProvider.overrideWithValue(previews),
    ],
    child: MaterialApp.router(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  if (editing != null) {
    // The form is always opened from the trip it edits, already loaded: it
    // fills itself in from that trip once, after its first frame.
    ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
        .read(itineraryDetailProvider(kTripId));
    await tester.pumpAndSettle();
  }
  router.push(editing == null
      ? '/itineraries/$kTripId/stops/new'
      : '/itineraries/$kTripId/stops/${editing['id']}/edit');
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(tester.element(find.byType(StopFormScreen)))!;
  return _Harness(api, geocoding, previews, l10n);
}

Finder get _searchField => find.descendant(
    of: find.byType(PlaceSearchBox), matching: find.byType(TextField));

Finder get _nameField => find.byType(TextFormField).first;

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(_searchField, text);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Future<void> _openGoogleSegment(WidgetTester tester, _Harness h) async {
  await tester.tap(find.text(h.l10n.locationModeGoogleMaps));
  await tester.pumpAndSettle();
}

const _louvre = PlaceSuggestion(
  displayName: 'Louvre',
  address: 'Rue de Rivoli, Paris, France',
  lat: 48.8606,
  lng: 2.3376,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('OpenStreetMap is searched on submit, never while typing',
      (tester) async {
    final h = await _pumpForm(tester);

    await tester.enterText(_searchField, 'louvre');
    await tester.pump(const Duration(seconds: 2));
    expect(h.geocoding.queries, isEmpty);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.geocoding.queries, ['louvre']);
  });

  testWidgets('an OSM pick fills the address, and the name only when empty',
      (tester) async {
    await _pumpForm(tester, osmResults: [_louvre]);
    await tester.enterText(_nameField, 'Morning at the museum');
    await _search(tester, 'louvre');

    await tester.tap(find.text('Louvre'));
    await tester.pumpAndSettle();

    expect(find.text('Morning at the museum'), findsOneWidget);
    // The address fills its field; the list (the only other place it showed)
    // closed on the pick.
    expect(find.text('Rue de Rivoli, Paris, France'), findsOneWidget);
    expect(find.text('Louvre'), findsNothing);
  });

  testWidgets(
      'in the Google Maps segment an empty OSM answer asks Google, and a pick '
      'keeps only the place ID and what the user typed', (tester) async {
    final h = await _pumpForm(tester);
    await _openGoogleSegment(tester, h);
    await tester.enterText(_nameField, 'Lunch');

    await _search(tester, 'chez marcel');

    expect(h.geocoding.queries, ['chez marcel']);
    expect(h.api.lines, contains('POST $kGooglePlaceAutocompleteEndpoint'));
    // Google's attribution, under its suggestions.
    expect(
        find.descendant(
            of: find.byType(PlaceSearchBox), matching: find.text('Google Maps')),
        findsOneWidget);
    await tester.tap(find.text(_googleName));
    await tester.pumpAndSettle();

    // The title stays the user's: never prefilled from Google.
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text(h.l10n.googlePlaceSearchedAs('chez marcel')), findsOneWidget);

    await tester.tap(find.text(h.l10n.save));
    await tester.pumpAndSettle();

    final body = h.savedStop;
    expect(body['place_name'], 'Lunch');
    expect(body['place_source'], 'google');
    expect(body['google_place_id'], _placeId);
    expect(body['google_place_query'], 'chez marcel');
    expect([body['lat'], body['lng'], body['map_url'], body['place_address']],
        [null, null, null, null]);
    expect(body.toString().contains('SENTINEL'), isFalse,
        reason: "nothing Google returned is ever sent back to be stored");
  });

  testWidgets('OSM results offer Google, which asks only when tapped',
      (tester) async {
    final h = await _pumpForm(tester, osmResults: [_louvre]);
    await _openGoogleSegment(tester, h);

    await _search(tester, 'louvre');
    expect(find.text('Louvre'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(h.api.lines.where((l) => l.contains('/places/')), isEmpty);

    await tester.tap(find.text(h.l10n.searchOnGoogleMaps));
    await tester.pumpAndSettle();

    expect(h.api.lines, contains('POST $kGooglePlaceAutocompleteEndpoint'));
    expect(find.text(_googleName), findsOneWidget);
  });

  testWidgets('without Google search the Coordinates segment says OSM found '
      'nothing, and never asks Google', (tester) async {
    final h = await _pumpForm(tester);

    await _search(tester, 'nowhere at all');

    expect(find.text(h.l10n.placeSearchNoResults), findsOneWidget);
    expect(h.api.lines.where((l) => l.contains('/places/')), isEmpty);
  });

  testWidgets(
      'a pasted short link fetches nothing, says it cannot go on the map, '
      'and saves without coordinates', (tester) async {
    final h = await _pumpForm(tester);
    await _openGoogleSegment(tester, h);
    await tester.enterText(_nameField, 'Hidden gem');

    final link = find.widgetWithText(TextFormField, h.l10n.mapLinkHint);
    await tester.ensureVisible(link);
    await tester.enterText(link, 'https://maps.app.goo.gl/abc123');
    await tester.pumpAndSettle();

    expect(find.text(h.l10n.mapLinkShortLinkHint), findsOneWidget);
    expect(h.previews.fetched, isEmpty);

    await tester.tap(find.text(h.l10n.save));
    await tester.pumpAndSettle();

    final body = h.savedStop;
    expect(body['map_url'], 'https://maps.app.goo.gl/abc123');
    expect(body['place_source'], 'link');
    expect([body['lat'], body['lng']], [null, null]);
    expect(h.previews.fetched, isEmpty);
    // Only our own API was asked anything.
    for (final request in h.api.sent) {
      expect(request.uri.host, Uri.parse(kApiBaseUrl).host);
    }
  });

  testWidgets("a full link's coordinates are never saved", (tester) async {
    final h = await _pumpForm(tester);
    await _openGoogleSegment(tester, h);
    await tester.enterText(_nameField, 'Tower');

    final link = find.widgetWithText(TextFormField, h.l10n.mapLinkHint);
    await tester.ensureVisible(link);
    await tester.enterText(link,
        'https://www.google.com/maps/place/Eiffel+Tower/@48.8583,2.2944,17z');
    await tester.pumpAndSettle();
    // Its text places it: no hint.
    expect(find.text(h.l10n.mapLinkShortLinkHint), findsNothing);

    await tester.tap(find.text(h.l10n.save));
    await tester.pumpAndSettle();

    expect([h.savedStop['lat'], h.savedStop['lng']], [null, null]);
    expect(h.previews.fetched, isEmpty);
  });

  group('editing a stop', () {
    testWidgets(
        'Given a Google stop, When only its name changes, Then the save leaves '
        'its place to the server', (tester) async {
      final h = await _pumpForm(tester, editing: _googleStopJson('g1'));
      expect(find.byKey(StopFormScreen.googlePlaceCardKey), findsOneWidget);

      await tester.enterText(_nameField, 'Long lunch');
      await tester.tap(find.text(h.l10n.save));
      await tester.pumpAndSettle();

      final body = h.savedStop;
      expect(body['place_name'], 'Long lunch');
      // An ID the yearly refresh may have replaced is never written back.
      for (final key in ['place_source', 'google_place_id', 'google_place_query']) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
      expect([body['lat'], body['lng'], body['map_url']], [null, null, null]);
    });

    testWidgets(
        'Given a Google stop Google lost, When the form opens, Then it says so '
        'and the search starts from the old words', (tester) async {
      final h = await _pumpForm(tester,
          editing: _googleStopJson('g1', missing: true));

      expect(find.text(h.l10n.googlePlaceMissing), findsOneWidget);
      expect(find.text(h.l10n.googlePlaceSearchAgain), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(PlaceSearchBox.fieldKey));
      expect(field.controller!.text, 'chez marcel');
    });

    testWidgets(
        'Given a Google stop, When it is saved from the Coordinates segment '
        'with no coordinates, Then its Google place is cleared', (tester) async {
      final h = await _pumpForm(tester, editing: _googleStopJson('g1'));

      await tester.tap(find.text(h.l10n.locationModeCoordinates));
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l10n.save));
      await tester.pumpAndSettle();

      final body = h.savedStop;
      expect(body.containsKey('google_place_id'), isTrue);
      expect([body['google_place_id'], body['google_place_query'], body['map_url']],
          [null, null, null]);
    });
  });

  testWidgets(
      'Given a picked Google place, When Change is tapped, Then the card goes '
      'and the search holds its words', (tester) async {
    final h = await _pumpForm(tester);
    await _openGoogleSegment(tester, h);
    await _search(tester, 'chez marcel');
    await tester.tap(find.text(_googleName));
    await tester.pumpAndSettle();
    expect(find.byKey(StopFormScreen.googlePlaceCardKey), findsOneWidget);

    await tester.tap(find.text(h.l10n.googlePlaceChange));
    await tester.pumpAndSettle();

    expect(find.byKey(StopFormScreen.googlePlaceCardKey), findsNothing);
    final field = tester.widget<TextField>(find.byKey(PlaceSearchBox.fieldKey));
    expect(field.controller!.text, 'chez marcel');
  });

  testWidgets('Given typed coordinates, When saved, Then the source is typed',
      (tester) async {
    final h = await _pumpForm(tester);
    await tester.enterText(_nameField, 'Viewpoint');
    await tester.enterText(find.byKey(StopFormScreen.latFieldKey), '45.8326');
    await tester.enterText(find.byKey(StopFormScreen.lngFieldKey), '6.8652');
    await tester.pumpAndSettle();

    await tester.tap(find.text(h.l10n.save));
    await tester.pumpAndSettle();

    final body = h.savedStop;
    expect(body['place_source'], 'typed');
    expect([body['lat'], body['lng']], [45.8326, 6.8652]);
    expect(body['map_url'], isNull);
  });

  testWidgets(
      'Given the trip already has a Google place, When the same place is '
      'picked, Then the form warns it is already in the trip', (tester) async {
    final h = await _pumpForm(tester, others: [_googleStopJson('g1')]);
    await _openGoogleSegment(tester, h);
    await tester.enterText(_nameField, 'Second lunch');

    await _search(tester, 'chez marcel');
    await tester.tap(find.text(_googleName));
    await tester.pumpAndSettle();

    expect(find.text(h.l10n.alreadyInItinerary('Lunch')), findsOneWidget);
  });
}
