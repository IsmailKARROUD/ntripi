// test/widgets/locations_map_test.dart
//
// Regression tests for the profile "Where I've been" maps.
//
// A user with a single visited location (or several at the same coordinate)
// produces a zero-area LatLngBounds. Feeding that to flutter_map's
// CameraFit.bounds without a finite maxZoom makes the fit compute zoom=Infinity
// -> NaN camera -> an infinite tile grid, which froze the app (ANR) when
// returning from the edit-profile screen. Both maps now cap the fit with
// maxZoom.
//
// These tests are safe (they never hang the suite): in a debug/test build the
// missing guard surfaces as flutter_map's MapCamera `assert(zoom.isFinite)`
// throwing during layout — a fast fail caught by `tester.takeException()`.
//
// Two maps use CameraFit.bounds and are covered here:
//   - ProfileMapHero (the hero that actually froze)
//   - FullscreenLocationsMapScreen
// The itinerary-detail and map-picker maps use a fixed initialCenter/initialZoom
// (no bounds fit), so they carry no degenerate-fit risk and are not tested here.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
import 'package:social_flutter/features/profile/presentation/fullscreen_locations_map_screen.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_chrome.dart';
import 'package:social_flutter/features/profile/providers/user_locations_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

VisitedLocation _loc(double lat, double lng) => VisitedLocation(
      lat: lat,
      lng: lng,
      itineraryId: 'i1',
      stopId: 's-$lat-$lng',
    );

class _FakeUserLocations extends UserLocationsNotifier {
  _FakeUserLocations(this._items) : super(''); // family arg unused by the fake
  final List<VisitedLocation> _items;
  @override
  Future<List<VisitedLocation>> build() async => _items;
}

void _setSurface(WidgetTester tester) {
  // A defined surface gives the map a real laid-out size to fit against.
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _heroApp(List<VisitedLocation> locations) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          height: 200,
          width: 400,
          child: ProfileMapHero(
            isSelf: true,
            totalStops: locations.length,
            isPrivate: false,
            locations: locations,
          ),
        ),
      ),
    );

Widget _fullscreenApp(List<VisitedLocation> locations) => ProviderScope(
      overrides: [
        userLocationsProvider
            .overrideWith2((_) => _FakeUserLocations(locations)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home:
            const FullscreenLocationsMapScreen(userId: 'u1', userName: 'Ana'),
      ),
    );

// Pump enough frames for flutter_map to apply initialCameraFit after layout.
// Plain pumps (not pumpAndSettle) avoid spinning on tile-load retry timers.
Future<void> _settleMap(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('ProfileMapHero — no degenerate-bounds freeze', () {
    testWidgets(
        'Given a single visited location, When the hero builds, '
        'Then it fits without a non-finite-zoom crash', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_heroApp([_loc(48.8566, 2.3522)]));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets(
        'Given several locations at the exact same coordinate, '
        'When the hero builds, Then it fits without a crash', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_heroApp([
        _loc(40.4168, -3.7038),
        _loc(40.4168, -3.7038),
        _loc(40.4168, -3.7038),
      ]));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets(
        'Given no visited locations, When the hero builds, '
        'Then the world-map fallback renders without a crash', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_heroApp(const []));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets(
        'Given several distinct locations, When the hero builds, '
        'Then the normal fit path still works', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_heroApp([
        _loc(48.8566, 2.3522), // Paris
        _loc(41.3874, 2.1686), // Barcelona
        _loc(52.5200, 13.4050), // Berlin
      ]));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });

  group('FullscreenLocationsMapScreen — no degenerate-bounds freeze', () {
    testWidgets(
        'Given a single visited location, When the map builds, '
        'Then it fits without a non-finite-zoom crash', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_fullscreenApp([_loc(48.8566, 2.3522)]));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets(
        'Given several locations at the exact same coordinate, '
        'When the map builds, Then it fits without a crash', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_fullscreenApp([
        _loc(40.4168, -3.7038),
        _loc(40.4168, -3.7038),
      ]));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets(
        'Given several distinct locations, When the map builds, '
        'Then the normal fit path still works', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_fullscreenApp([
        _loc(48.8566, 2.3522),
        _loc(41.3874, 2.1686),
      ]));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets(
        'Given no visited locations, When the screen builds, '
        'Then the empty state shows and no map is built', (tester) async {
      _setSurface(tester);

      await tester.pumpWidget(_fullscreenApp(const []));
      await _settleMap(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('No stops yet'), findsOneWidget);
    });
  });
}
