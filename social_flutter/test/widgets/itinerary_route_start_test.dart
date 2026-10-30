// test/widgets/itinerary_route_start_test.dart — the route arrow above a
// trip's stops asks where the Google Maps route starts before opening it.
//
// From my location starts at the device (Google offers turn-by-turn), from the
// first stop shows the trip alone; dismissing the question opens nothing, and a
// route cut to Google's cap names the number of stops the chosen start carries.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/data/maps_launcher_service.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/trip_json.dart';
import '../support/url_launches.dart';

/// Harbour, then Museum or Market, then Beach — every stop on the map.
Itinerary _trip() => Itinerary.fromJson(tripJson(
      canEdit: false,
      tracks: [
        trackJson('t1', [
          stopJson('s1', trackId: 't1', placeName: 'Harbour', lat: 10, lng: 20),
        ], rank: 'a'),
        trackJson('t2', [
          stopJson('s2', trackId: 't2', placeName: 'Museum', lat: 11, lng: 21),
          stopJson('s3', trackId: 't2', placeName: 'Market', lat: 12, lng: 22),
        ], rank: 'b'),
        trackJson('t3', [
          stopJson('s4', trackId: 't3', placeName: 'Beach', lat: 13, lng: 23),
        ], rank: 'c'),
      ],
    ));

/// Harbour, then a stop with no place on the map, then optionally Beach.
Itinerary _tripWithUnmappedStop({bool beach = true}) =>
    Itinerary.fromJson(tripJson(
      canEdit: false,
      tracks: [
        trackJson('t1', [
          stopJson('s1', trackId: 't1', placeName: 'Harbour', lat: 10, lng: 20),
        ], rank: 'a'),
        trackJson('t2', [
          stopJson('s2', trackId: 't2', placeName: 'Somewhere'),
        ], rank: 'b'),
        if (beach)
          trackJson('t3', [
            stopJson('s3', trackId: 't3', placeName: 'Beach', lat: 13, lng: 23),
          ], rank: 'c'),
      ],
    ));

/// [count] stops one after another, stop i at (10 + i, 20 + i).
Itinerary _tripOfStops(int count) => Itinerary.fromJson(tripJson(
      canEdit: false,
      tracks: [
        for (var i = 0; i < count; i++)
          trackJson('t$i', [
            stopJson('s$i',
                trackId: 't$i',
                placeName: 'Stop $i',
                lat: 10.0 + i,
                lng: 20.0 + i),
          ], rank: String.fromCharCode(0x61 + i)),
      ],
    ));

/// Stop i of [_tripOfStops], as Google Maps gets it.
String _coords(int i) => '${10.0 + i},${20.0 + i}';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo(this.trip) : super(Dio());

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

/// Records the routes the trip page asks Google Maps for, and opens nothing.
class _RecordingLauncher extends MapsLauncherService {
  final opened = <(List<LatLng>, RouteStart)>[];
  // What openRoute answers: whether the route was cut to the cap.
  bool truncates = false;

  @override
  Future<bool> openRoute(
    List<LatLng> orderedPoints, {
    required RouteStart start,
  }) async {
    opened.add((orderedPoints, start));
    return truncates;
  }
}

/// A viewer's trip page, read mode. Without [launcher] the real one opens the
/// route — through url_launcher, which a test records.
Future<AppLocalizations> _pump(
  WidgetTester tester, {
  Itinerary? trip,
  MapsLauncherService? launcher,
}) async {
  // Tall enough that the stops header is on screen without scrolling.
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_FakeRepo(trip ?? _trip())),
      myProfileProvider.overrideWith(_Viewer.new),
      if (launcher != null)
        mapsLauncherServiceProvider.overrideWithValue(launcher),
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

Future<void> _tapRouteArrow(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byTooltip(l10n.openRouteInMaps));
  await tester.pumpAndSettle();
}

/// Opens the question and answers it with [start].
Future<void> _openRoute(
    WidgetTester tester, AppLocalizations l10n, RouteStart start) async {
  await _tapRouteArrow(tester, l10n);
  await tester.tap(find.text(start == RouteStart.firstStop
      ? l10n.routeFromFirstStop
      : l10n.routeFromMyLocation));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('the route arrow asks where to start and opens nothing yet',
      (tester) async {
    final launcher = _RecordingLauncher();
    final l10n = await _pump(tester, launcher: launcher);

    await _tapRouteArrow(tester, l10n);

    expect(find.text(l10n.routeFromMyLocation), findsOneWidget);
    expect(find.text(l10n.routeFromMyLocationHint), findsOneWidget);
    expect(find.text(l10n.routeFromFirstStop), findsOneWidget);
    expect(find.text(l10n.routeFromFirstStopHint), findsOneWidget);
    expect(launcher.opened, isEmpty);
  });

  testWidgets('from the first stop opens the trip alone, one stop per track',
      (tester) async {
    final launcher = _RecordingLauncher();
    final l10n = await _pump(tester, launcher: launcher);

    await _openRoute(tester, l10n, RouteStart.firstStop);

    final (points, start) = launcher.opened.single;
    expect(start, RouteStart.firstStop);
    // Museum, not Market: the route takes the alternative on screen.
    expect(points, const [LatLng(10, 20), LatLng(11, 21), LatLng(13, 23)]);
    expect(find.text(l10n.routeFromFirstStop), findsNothing);
    // Nothing was cut, so nothing is said.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('from my location opens the route from the device location',
      (tester) async {
    final launcher = _RecordingLauncher();
    final l10n = await _pump(tester, launcher: launcher);

    await _openRoute(tester, l10n, RouteStart.myLocation);

    final (points, start) = launcher.opened.single;
    expect(start, RouteStart.myLocation);
    expect(points, const [LatLng(10, 20), LatLng(11, 21), LatLng(13, 23)]);
    expect(find.text(l10n.routeFromMyLocation), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('dismissing the question opens nothing', (tester) async {
    final launcher = _RecordingLauncher();
    final l10n = await _pump(tester, launcher: launcher);

    await _tapRouteArrow(tester, l10n);
    // The barrier above the sheet.
    await tester.tapAt(const Offset(540, 20));
    await tester.pumpAndSettle();

    expect(find.text(l10n.routeFromMyLocation), findsNothing);
    expect(launcher.opened, isEmpty);
  });

  for (final (start, cap) in [
    (RouteStart.firstStop, 11),
    (RouteStart.myLocation, 10),
  ]) {
    testWidgets('a route cut short from ${start.name} names its $cap stops',
        (tester) async {
      final launcher = _RecordingLauncher()..truncates = true;
      final l10n = await _pump(tester, launcher: launcher);

      await _openRoute(tester, l10n, start);

      expect(find.text(l10n.routeTruncated(cap)), findsOneWidget);
    });
  }

  testWidgets('with the other alternative on screen, the route goes through it',
      (tester) async {
    final launcher = _RecordingLauncher();
    final l10n = await _pump(tester, launcher: launcher);

    // Swipe the middle track from Museum to Market.
    await tester.fling(find.text('Museum'), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();
    await _openRoute(tester, l10n, RouteStart.firstStop);

    final (points, _) = launcher.opened.single;
    expect(points, const [LatLng(10, 20), LatLng(12, 22), LatLng(13, 23)]);
  });

  testWidgets('a stop with no place on the map is left out of the route',
      (tester) async {
    final launcher = _RecordingLauncher();
    final l10n =
        await _pump(tester, trip: _tripWithUnmappedStop(), launcher: launcher);

    await _openRoute(tester, l10n, RouteStart.firstStop);

    final (points, _) = launcher.opened.single;
    expect(points, const [LatLng(10, 20), LatLng(13, 23)]);
  });

  testWidgets('with fewer than two stops on the map there is no route arrow',
      (tester) async {
    final l10n = await _pump(tester,
        trip: _tripWithUnmappedStop(beach: false),
        launcher: _RecordingLauncher());

    // Harbour alone is no route: Google Maps needs somewhere to go.
    expect(find.text('Somewhere'), findsOneWidget);
    expect(find.byTooltip(l10n.openRouteInMaps), findsNothing);
  });

  group('with the real launcher', () {
    testWidgets(
        'an 11-stop trip from the first stop reaches Google Maps whole, with '
        'nothing to say', (tester) async {
      final launches = recordUrlLaunches();
      final l10n = await _pump(tester, trip: _tripOfStops(11));

      await _openRoute(tester, l10n, RouteStart.firstStop);

      final route = launches.single.url.queryParameters;
      expect(route['origin'], _coords(0));
      expect(route['waypoints'],
          [for (var i = 1; i <= 9; i++) _coords(i)].join('|'));
      expect(route['destination'], _coords(10));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'the same trip from my location keeps its first 10 stops and says so',
        (tester) async {
      final launches = recordUrlLaunches();
      final l10n = await _pump(tester, trip: _tripOfStops(11));

      await _openRoute(tester, l10n, RouteStart.myLocation);

      final route = launches.single.url.queryParameters;
      // No origin: Google starts at the device.
      expect(route.containsKey('origin'), isFalse);
      // Stop 9 is the one dropped; the last stop stays the destination.
      expect(route['waypoints'],
          [for (var i = 0; i <= 8; i++) _coords(i)].join('|'));
      expect(route['destination'], _coords(10));
      expect(find.text(l10n.routeTruncated(10)), findsOneWidget);
    });
  });
}
