// test/widgets/locations_map_test.dart
//
// Regression test for the profile "Where I've been" maps.
//
// A user with a single visited location (or several at the same coordinate)
// produces a zero-area LatLngBounds. Feeding that to flutter_map's
// CameraFit.bounds without a finite maxZoom makes the fit compute zoom=Infinity
// -> NaN camera -> an infinite tile grid, which froze the app (ANR) when
// returning from the edit-profile screen. The screens now cap the fit with
// maxZoom; this test ensures a single-location map builds instead of throwing
// flutter_map's `zoom.isFinite` assertion.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
import 'package:social_flutter/features/profile/presentation/fullscreen_locations_map_screen.dart';
import 'package:social_flutter/features/profile/providers/user_locations_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class _FakeUserLocations extends UserLocationsNotifier {
  _FakeUserLocations(this._items) : super(''); // family arg unused by the fake
  final List<VisitedLocation> _items;
  @override
  Future<List<VisitedLocation>> build() async => _items;
}

Widget _buildScreen(List<VisitedLocation> locations) => ProviderScope(
      overrides: [
        userLocationsProvider.overrideWith2((_) => _FakeUserLocations(locations)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FullscreenLocationsMapScreen(userId: 'u1', userName: 'Ana'),
      ),
    );

void main() {
  testWidgets(
      'Given a single visited location, When the map builds, '
      'Then it fits without a non-finite-zoom crash', (tester) async {
    await tester.pumpWidget(_buildScreen(const [
      VisitedLocation(
        lat: 48.8566,
        lng: 2.3522,
        itineraryId: 'i1',
        stopId: 's1',
      ),
    ]));
    // 1st pump resolves the async provider -> data branch; further pumps let
    // flutter_map apply initialCameraFit after the map has a laid-out size.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
