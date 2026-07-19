// Unit tests for maps_launcher_service.dart — the pure URI builders behind
// the "open in maps" actions. Detection and launching go through url_launcher
// platform channels and are exercised manually; these tests cover the link
// formats and the Google Maps waypoint-cap truncation.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/features/itineraries/data/maps_launcher_service.dart';

void main() {
  final service = MapsLauncherService();

  group('placeUri', () {
    test('Google Maps uses the search URL API with raw coordinates', () {
      final uri = service.placeUri(ExternalMapApp.googleMaps,
          lat: 48.8566, lng: 2.3522, label: 'Louvre');

      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      expect(uri.queryParameters['api'], '1');
      // Coordinates, not the label — coords are exact, a name search is not.
      expect(uri.queryParameters['query'], '48.8566,2.3522');
    });

    test('Waze uses the universal link with navigate=yes', () {
      final uri = service.placeUri(ExternalMapApp.waze,
          lat: 48.8566, lng: 2.3522);

      expect(uri.host, 'waze.com');
      expect(uri.path, '/ul');
      expect(uri.queryParameters['ll'], '48.8566,2.3522');
      expect(uri.queryParameters['navigate'], 'yes');
    });

    test('Apple Maps carries the place label as the pin name', () {
      final uri = service.placeUri(ExternalMapApp.appleMaps,
          lat: 48.8566, lng: 2.3522, label: 'Musée du Louvre');

      expect(uri.host, 'maps.apple.com');
      expect(uri.queryParameters['ll'], '48.8566,2.3522');
      expect(uri.queryParameters['q'], 'Musée du Louvre');
    });

    test('Apple Maps omits q when the label is null or blank', () {
      final noLabel =
          service.placeUri(ExternalMapApp.appleMaps, lat: 1.0, lng: 2.0);
      final blankLabel = service.placeUri(ExternalMapApp.appleMaps,
          lat: 1.0, lng: 2.0, label: '   ');

      expect(noLabel.queryParameters.containsKey('q'), isFalse);
      expect(blankLabel.queryParameters.containsKey('q'), isFalse);
    });

    test('HERE WeGo embeds coordinates and label in the path', () {
      final uri = service.placeUri(ExternalMapApp.hereWeGo,
          lat: 48.8566, lng: 2.3522, label: 'Louvre');

      expect(uri.host, 'share.here.com');
      expect(uri.path, '/l/48.8566,2.3522,Louvre');
      expect(uri.queryParameters['p'], 'yes');
    });

    test('Yandex Maps uses longitude,latitude order (its own convention)', () {
      final uri = service.placeUri(ExternalMapApp.yandexMaps,
          lat: 48.8566, lng: 2.3522);

      expect(uri.host, 'yandex.com');
      // pt is lon,lat — the reverse of every other app here.
      expect(uri.queryParameters['pt'], '2.3522,48.8566');
    });

    test('Citymapper routes to the coordinate as its destination', () {
      final uri = service.placeUri(ExternalMapApp.citymapper,
          lat: 48.8566, lng: 2.3522, label: 'Louvre');

      expect(uri.host, 'citymapper.com');
      expect(uri.path, '/directions');
      expect(uri.queryParameters['endcoord'], '48.8566,2.3522');
      expect(uri.queryParameters['endname'], 'Louvre');
    });

    test('OsmAnd uses its iOS scheme with lat/lon params', () {
      final uri = service.placeUri(ExternalMapApp.osmAnd,
          lat: 48.8566, lng: 2.3522);

      expect(uri.scheme, 'osmandmaps');
      expect(uri.queryParameters['lat'], '48.8566');
      expect(uri.queryParameters['lon'], '2.3522');
    });

    test('OpenStreetMap drops a marker and sets the view fragment', () {
      final uri = service.placeUri(ExternalMapApp.openStreetMap,
          lat: 48.8566, lng: 2.3522);

      expect(uri.host, 'www.openstreetmap.org');
      expect(uri.queryParameters['mlat'], '48.8566');
      expect(uri.queryParameters['mlon'], '2.3522');
      expect(uri.fragment, 'map=16/48.8566/2.3522');
    });

    test('otherApps builds a standard geo: URI with a label', () {
      final uri = service.placeUri(ExternalMapApp.otherApps,
          lat: 48.8566, lng: 2.3522, label: 'Louvre');

      expect(uri.scheme, 'geo');
      expect(uri.toString(), 'geo:48.8566,2.3522?q=48.8566,2.3522(Louvre)');
    });
  });

  group('routeUri', () {
    List<LatLng> points(int n) =>
        List.generate(n, (i) => LatLng(10.0 + i, 20.0 + i));

    test('omits origin so Google navigates from the device location', () {
      final uri = service.routeUri(points(2));

      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      // No origin — Google defaults to the device location, which is what
      // makes the app offer Start instead of a static preview.
      expect(uri.queryParameters.containsKey('origin'), isFalse);
      expect(uri.queryParameters['destination'], '11.0,21.0');
      expect(uri.queryParameters['waypoints'], '10.0,20.0');
    });

    test('all stops before the last become pipe-separated waypoints in order',
        () {
      final uri = service.routeUri(points(5));

      expect(uri.queryParameters['destination'], '14.0,24.0');
      expect(uri.queryParameters['waypoints'],
          '10.0,20.0|11.0,21.0|12.0,22.0|13.0,23.0');
    });

    test('routes over the cap keep the first 9 stops and the destination',
        () {
      final uri = service.routeUri(points(15));

      // Destination is preserved even though middle stops were dropped.
      expect(uri.queryParameters['destination'], '24.0,34.0');
      final waypoints = uri.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, MapsLauncherService.maxGoogleWaypoints);
      expect(waypoints.first, '10.0,20.0');
      expect(waypoints.last, '18.0,28.0');
    });

    test('routes at the cap (10 points) are not truncated', () {
      final uri = service.routeUri(points(10));

      final waypoints = uri.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, MapsLauncherService.maxGoogleWaypoints);
      expect(uri.queryParameters['destination'], '19.0,29.0');
    });
  });
}
