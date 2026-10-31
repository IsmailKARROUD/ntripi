// Unit tests for maps_launcher_service.dart — the pure URI builders behind
// the "open in maps" actions. Detection goes through url_launcher's platform
// channel and is exercised manually; these tests cover the link formats, the
// Google Maps waypoint-cap truncation, and the route openRoute hands that
// channel.

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/maps_launcher_service.dart';
import 'package:ntripi/features/itineraries/domain/map_point.dart';

import '../support/url_launches.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  List<MapPoint> points(int n) =>
      List.generate(n, (i) => CoordPoint(10.0 + i, 20.0 + i));

  group('routeUri from my location', () {
    Uri routeUri(List<MapPoint> points) =>
        service.routeUri(points, start: RouteStart.myLocation);

    test('omits origin so Google navigates from the device location', () {
      final uri = routeUri(points(2));

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
      final uri = routeUri(points(5));

      expect(uri.queryParameters['destination'], '14.0,24.0');
      expect(uri.queryParameters['waypoints'],
          '10.0,20.0|11.0,21.0|12.0,22.0|13.0,23.0');
    });

    test('routes over the cap keep the first 9 stops and the destination',
        () {
      final uri = routeUri(points(15));

      // Destination is preserved even though middle stops were dropped.
      expect(uri.queryParameters['destination'], '24.0,34.0');
      final waypoints = uri.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, MapsLauncherService.maxGoogleWaypoints);
      expect(waypoints.first, '10.0,20.0');
      expect(waypoints.last, '18.0,28.0');
    });

    test('routes at the cap (10 points) are not truncated', () {
      final uri = routeUri(points(10));

      final waypoints = uri.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, MapsLauncherService.maxGoogleWaypoints);
      expect(uri.queryParameters['destination'], '19.0,29.0');
    });
  });

  group('routeUri from the first stop', () {
    Uri routeUri(List<MapPoint> points) =>
        service.routeUri(points, start: RouteStart.firstStop);

    test('the first stop is the origin, so Google shows the trip alone', () {
      final uri = routeUri(points(5));

      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['origin'], '10.0,20.0');
      // The origin is not repeated as a waypoint.
      expect(uri.queryParameters['waypoints'], '11.0,21.0|12.0,22.0|13.0,23.0');
      expect(uri.queryParameters['destination'], '14.0,24.0');
    });

    test('two stops are an origin and a destination, with no waypoints', () {
      final uri = routeUri(points(2));

      expect(uri.queryParameters['origin'], '10.0,20.0');
      expect(uri.queryParameters['destination'], '11.0,21.0');
      expect(uri.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('routes over the cap keep the origin, 9 waypoints and the destination',
        () {
      final uri = routeUri(points(15));

      expect(uri.queryParameters['origin'], '10.0,20.0');
      final waypoints = uri.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, MapsLauncherService.maxGoogleWaypoints);
      expect(waypoints.first, '11.0,21.0');
      expect(waypoints.last, '19.0,29.0');
      expect(uri.queryParameters['destination'], '24.0,34.0');
    });

    test('routes at the cap (11 points) are not truncated', () {
      final uri = routeUri(points(11));

      expect(uri.queryParameters['origin'], '10.0,20.0');
      final waypoints = uri.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, MapsLauncherService.maxGoogleWaypoints);
      expect(uri.queryParameters['destination'], '20.0,30.0');
    });
  });

  group('Google places', () {
    const tower = PlacePoint('ChIJLU7jZClu5kcR4PcOOO6p3I0', 'eiffel tower');
    const louvre = PlacePoint('ChIJD3uTd9hx5kcR1IQvGfr8dbk', 'louvre');

    test('a place opens by its ID, with the search text Maps URLs require', () {
      final uri = service.googlePlaceUri(tower.placeId, tower.fallbackText);

      expect(uri.path, '/maps/search/');
      expect(uri.queryParameters, {
        'api': '1',
        'query': 'eiffel tower',
        'query_place_id': 'ChIJLU7jZClu5kcR4PcOOO6p3I0',
      });
    });

    test('a lost place is only searched for by its text', () {
      final uri = service.googleSearchUri('eiffel tower');

      expect(uri.queryParameters, {'api': '1', 'query': 'eiffel tower'});
    });

    test('origin and destination carry their own place IDs', () {
      final uri = service.routeUri(
        [tower, const CoordPoint(1.5, 2.5), louvre],
        start: RouteStart.firstStop,
      );

      expect(uri.queryParameters['origin'], 'eiffel tower');
      expect(uri.queryParameters['origin_place_id'], tower.placeId);
      expect(uri.queryParameters['destination'], 'louvre');
      expect(uri.queryParameters['destination_place_id'], louvre.placeId);
      expect(uri.queryParameters['waypoints'], '1.5,2.5');
    });

    test('waypoint IDs go only when every waypoint has one', () {
      final all = service.routeUri(
        [const CoordPoint(1, 2), tower, louvre, const CoordPoint(3, 4)],
        start: RouteStart.firstStop,
      );
      expect(all.queryParameters['waypoints'], 'eiffel tower|louvre');
      expect(all.queryParameters['waypoint_place_ids'],
          '${tower.placeId}|${louvre.placeId}');

      final mixed = service.routeUri(
        [const CoordPoint(1, 2), tower, const CoordPoint(5, 6), const CoordPoint(3, 4)],
        start: RouteStart.firstStop,
      );
      expect(mixed.queryParameters['waypoints'], 'eiffel tower|5.0,6.0');
      expect(mixed.queryParameters.containsKey('waypoint_place_ids'), isFalse);
    });

    test('from my location the first place is a waypoint, never an origin', () {
      final uri = service.routeUri([tower, louvre], start: RouteStart.myLocation);

      expect(uri.queryParameters.containsKey('origin'), isFalse);
      expect(uri.queryParameters.containsKey('origin_place_id'), isFalse);
      expect(uri.queryParameters['waypoint_place_ids'], tower.placeId);
    });
  });

  test('a route carries one more stop from the first stop than from here', () {
    // Google's waypoint cap excludes the origin and the destination.
    expect(MapsLauncherService.maxRouteStops(RouteStart.myLocation), 10);
    expect(MapsLauncherService.maxRouteStops(RouteStart.firstStop), 11);
  });

  group('openRoute', () {
    test('hands the route to the Maps app, or to the browser without it',
        () async {
      final launches = recordUrlLaunches();
      final route = points(3);

      await service.openRoute(route, start: RouteStart.firstStop);

      final launch = launches.single;
      expect(launch.url, service.routeUri(route, start: RouteStart.firstStop));
      // An in-app browser view would keep the Google Maps app out of it…
      expect(launch.inApp, isFalse);
      // …and app-only would open nothing on a phone without it.
      expect(launch.appOnly, isFalse);
    });

    for (final (start, stops, cut) in [
      (RouteStart.myLocation, 10, false),
      (RouteStart.myLocation, 11, true),
      (RouteStart.firstStop, 11, false),
      (RouteStart.firstStop, 12, true),
    ]) {
      test(
          'from ${start.name}, $stops stops '
          '${cut ? 'are reported cut short' : 'open whole'}', () async {
        final launches = recordUrlLaunches();

        final truncated = await service.openRoute(points(stops), start: start);

        expect(truncated, cut);
        expect(launches, hasLength(1));
      });
    }

    test('a route of one stop is refused before anything opens', () async {
      final launches = recordUrlLaunches();

      await expectLater(
          service.openRoute(points(1), start: RouteStart.myLocation),
          throwsAssertionError);
      expect(launches, isEmpty);
    });
  });
}
