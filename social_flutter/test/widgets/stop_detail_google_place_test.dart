// The stop page of a Google place, a link and an OSM stop: what opens Google
// Maps, the credit line under the location, and what an editor is told when
// Google has lost a place.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/data/link_preview_service.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/presentation/stop_detail_screen.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/translation/domain/translation.dart';
import 'package:ntripi/features/translation/providers/translation_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/url_launches.dart';

const _owner = 'user-1';
const _placeId = 'ChIJLU7jZClu5kcR4PcOOO6p3I0';

class _OneStopRepo extends ItineraryRepository {
  _OneStopRepo(this.stop) : super(Dio());

  final Stop stop;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 10, 31);
    return Itinerary(
      id: 'itin-1',
      userId: _owner,
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.onlyMe,
      createdAt: ts,
      updatedAt: ts,
      tracks: [
        Track(id: 'track-1', itineraryId: 'itin-1', rank: 'a', stops: [stop]),
      ],
    );
  }
}

class _Profile extends MyProfileNotifier {
  _Profile(this.userId);

  final String userId;

  @override
  Future<User> build() async => User(
        id: userId,
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

class _NoPreview extends LinkPreviewService {
  @override
  Future<LinkPreview?> fetch(String url) async => null;
}

Stop _stop({
  PlaceSource? source,
  String? placeId,
  String? query,
  bool missing = false,
  double? lat,
  double? lng,
  String? address,
  String? mapUrl,
}) =>
    Stop(
      id: 'stop-1',
      itineraryId: 'itin-1',
      trackId: 'track-1',
      rank: 'a',
      type: StopType.origin,
      placeName: 'Lunch',
      placeAddress: address,
      lat: lat,
      lng: lng,
      mapUrl: mapUrl,
      placeSource: source,
      googlePlaceId: placeId,
      googlePlaceQuery: query,
      googlePlaceMissing: missing,
      createdAt: DateTime.utc(2026, 10, 31),
    );

Future<AppLocalizations> _pump(WidgetTester tester, Stop stop,
    {String viewerId = _owner}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/itineraries/itin-1/stops/stop-1',
    routes: [
      GoRoute(
        path: '/itineraries/:id/stops/:stopId',
        builder: (_, s) => StopDetailScreen(
          itineraryId: s.pathParameters['id']!,
          stopId: s.pathParameters['stopId']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_OneStopRepo(stop)),
      myProfileProvider.overrideWith(() => _Profile(viewerId)),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      translationConfigProvider
          .overrideWith((ref) async => TranslationConfig.disabled),
      // Maps off: no WebView under test; the card keeps its open row.
      placesConfigProvider.overrideWith((ref) async =>
          const PlacesConfig(googleSearch: true, googleMaps: false)),
      linkPreviewServiceProvider.overrideWithValue(_NoPreview()),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(StopDetailScreen)))!;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a Google place opens in Google Maps by its ID, credited',
      (tester) async {
    final launches = recordUrlLaunches();
    final l10n = await _pump(tester,
        _stop(source: PlaceSource.google, placeId: _placeId, query: 'chez marcel'));

    expect(find.text('Google Maps'), findsOneWidget); // the credit line
    await tester.tap(find.text(l10n.linkPreviewOpensInMaps));
    await tester.pumpAndSettle();

    expect(launches.single.url.queryParameters, {
      'api': '1',
      'query': 'chez marcel',
      'query_place_id': _placeId,
    });
  });

  testWidgets("an OSM stop credits OpenStreetMap's contributors",
      (tester) async {
    final l10n = await _pump(tester,
        _stop(source: PlaceSource.osm, lat: 48.86, lng: 2.34, address: 'Paris'));

    expect(find.text(l10n.placeCreditOpenStreetMap), findsOneWidget);
    expect(find.text('Google Maps'), findsNothing);
  });

  testWidgets('a stop saved before sources existed carries no credit',
      (tester) async {
    final l10n = await _pump(tester, _stop(lat: 48.86, lng: 2.34));

    expect(find.text(l10n.placeCreditOpenStreetMap), findsNothing);
    expect(find.text('Google Maps'), findsNothing);
  });

  group('a place Google lost', () {
    final lost = _stop(
        source: PlaceSource.google,
        placeId: _placeId,
        query: 'chez marcel',
        missing: true);

    testWidgets('its editor is asked to find it again', (tester) async {
      final l10n = await _pump(tester, lost);

      expect(find.text(l10n.googlePlaceMissing), findsOneWidget);
      expect(find.text(l10n.googlePlaceSearchAgain), findsOneWidget);
    });

    testWidgets('a reader has no map and searches its words instead',
        (tester) async {
      final launches = recordUrlLaunches();
      final l10n = await _pump(tester, lost, viewerId: 'someone-else');

      expect(find.text(l10n.googlePlaceMissing), findsNothing);
      expect(find.text(l10n.linkPreviewOpensInMaps), findsNothing);
      await tester.tap(find.byTooltip(l10n.openInMaps));
      await tester.pumpAndSettle();

      expect(launches.single.url.queryParameters,
          {'api': '1', 'query': 'chez marcel'});
    });
  });
}
