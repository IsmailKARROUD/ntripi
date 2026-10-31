// The trip page's Map view is Google's route: there only while the server can
// draw Google maps, and honest about the stops it cannot place.
//
// The route itself (one point per track, the alternative on screen) is pinned
// in google_places_domain_test.dart; a WebView has no platform under test, so
// the cases here are the ones that build none.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/trip_json.dart';

class _Repo extends ItineraryRepository {
  _Repo(this.trip) : super(Dio());

  final Itinerary trip;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async =>
      trip;
}

class _Viewer extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-2',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

/// Two stops nothing places: a short link, and a place Google lost.
Itinerary _unplaceable() {
  final json = tripJson(canEdit: false, tracks: [
    trackJson('t1', [stopJson('s1', trackId: 't1', placeName: 'Gem')], rank: 'a'),
    trackJson('t2', [stopJson('s2', trackId: 't2', placeName: 'Lost')], rank: 'b'),
  ]);
  final tracks = json['tracks'] as List<dynamic>;
  ((tracks[0] as Map)['stops'] as List)[0]['map_url'] =
      'https://maps.app.goo.gl/abc';
  ((tracks[1] as Map)['stops'] as List)[0]
    ..['google_place_id'] = 'ChIJLU7jZClu5kcR4PcOOO6p3I0'
    ..['google_place_missing'] = true;
  return Itinerary.fromJson(json);
}

Future<AppLocalizations> _pump(WidgetTester tester, {required bool maps}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_Repo(_unplaceable())),
      myProfileProvider.overrideWith(_Viewer.new),
      placesConfigProvider.overrideWith((ref) async =>
          PlacesConfig(googleSearch: false, googleMaps: maps)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ItineraryDetailScreen(itineraryId: kTripId),
    ),
  ));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
      tester.element(find.byType(ItineraryDetailScreen)))!;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets('without Google maps there is no Map view to switch to',
      (tester) async {
    await _pump(tester, maps: false);

    expect(find.byIcon(Icons.map_rounded), findsNothing);
    expect(find.byIcon(Icons.list_rounded), findsNothing);
  });

  testWidgets('stops nothing places stay off the map, and the map says so',
      (tester) async {
    final l10n = await _pump(tester, maps: true);

    await tester.tap(find.byIcon(Icons.map_rounded));
    await tester.pumpAndSettle();

    expect(find.text(l10n.tripMapEmpty), findsOneWidget);
    expect(find.text(l10n.tripMapStopsNotShown(2)), findsOneWidget);
    // Two unplaced stops are no route: nothing to open.
    expect(find.byTooltip(l10n.openRouteInMaps), findsNothing);
  });
}
