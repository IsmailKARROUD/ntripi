// data/maps_launcher_service.dart — Detects installed map apps and builds the
// deep links used to open a stop's location or a full itinerary route.
//
// Launch strategy: https universal links wherever the app registers one (they
// open the native app when installed and the website otherwise, and also work
// on the web build). Apps without a usable universal link for arbitrary
// coordinates use their custom scheme (OsmAnd) or the platform `geo:` chooser.

import 'package:flutter/foundation.dart';
import 'package:ntripi/features/itineraries/domain/map_point.dart';
import 'package:url_launcher/url_launcher.dart';

enum ExternalMapApp {
  googleMaps,
  appleMaps,
  waze,
  hereWeGo,
  yandexMaps,
  citymapper,
  osmAnd,
  openStreetMap,
  // Android `geo:` chooser — surfaces OsmAnd, Organic Maps and any other
  // installed map app the OS knows about, which url_launcher can't target
  // individually by package.
  otherApps,
}

/// Where a Google Maps route link starts.
enum RouteStart {
  // No origin: Google starts at the device location — the only case where the
  // app offers Start (turn-by-turn) instead of a static preview.
  myLocation,
  // The trip's first stop is the origin: Google previews the trip alone.
  firstStop,
}

class MapsLauncherService {
  // Google Maps URL API hard cap on intermediate waypoints (origin +
  // destination excluded) — see maxRouteStops for what a link can carry.
  static const maxGoogleWaypoints = 9;

  /// Stops a route link can carry: the waypoints and the destination, plus the
  /// first stop when it is the origin — 10 from the device location, 11 from
  /// the first stop.
  static int maxRouteStops(RouteStart start) =>
      maxGoogleWaypoints + (start == RouteStart.firstStop ? 2 : 1);

  /// Map apps to offer in the picker, in display order.
  Future<List<ExternalMapApp>> installedApps() async {
    // canLaunchUrl can't probe schemes on web — offer the universal-link apps.
    if (kIsWeb) {
      return const [
        ExternalMapApp.googleMaps,
        ExternalMapApp.waze,
        ExternalMapApp.hereWeGo,
        ExternalMapApp.yandexMaps,
        ExternalMapApp.citymapper,
        ExternalMapApp.openStreetMap,
      ];
    }
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return [
      // Google Maps and OpenStreetMap always appear: their links fall back to
      // the browser, so the picker is never empty even with nothing installed.
      ExternalMapApp.googleMaps,
      if (isApple) ExternalMapApp.appleMaps,
      // Schemes are detection probes only; launches use the URIs from placeUri.
      if (await _canLaunch('waze://')) ExternalMapApp.waze,
      if (await _canLaunch('here-location://')) ExternalMapApp.hereWeGo,
      if (await _canLaunch('yandexmaps://')) ExternalMapApp.yandexMaps,
      if (await _canLaunch('citymapper://')) ExternalMapApp.citymapper,
      // OsmAnd is only targetable by scheme on Apple platforms; on Android it
      // is reached through the geo: chooser below.
      if (isApple && await _canLaunch('osmandmaps://')) ExternalMapApp.osmAnd,
      ExternalMapApp.openStreetMap,
      if (!isApple && await _canLaunch('geo:0,0')) ExternalMapApp.otherApps,
    ];
  }

  Future<bool> _canLaunch(String uri) async {
    try {
      return await canLaunchUrl(Uri.parse(uri));
    } on Exception {
      return false;
    }
  }

  Future<void> openPlace(
    ExternalMapApp app, {
    required double lat,
    required double lng,
    String? label,
  }) =>
      _launch(placeUri(app, lat: lat, lng: lng, label: label));

  /// Opens the route in Google Maps (the only app with multi-stop deep
  /// links). Returns true when the route was truncated to the waypoint cap.
  Future<bool> openRoute(
    List<MapPoint> orderedPoints, {
    required RouteStart start,
  }) async {
    assert(orderedPoints.length >= 2, 'a route needs at least two points');
    await _launch(routeUri(orderedPoints, start: start));
    return orderedPoints.length > maxRouteStops(start);
  }

  /// Opens a Google place in Google Maps by its ID. Maps URLs need no key.
  Future<void> openGooglePlace(String placeId, String query) =>
      _launch(googlePlaceUri(placeId, query));

  /// Searches Google Maps for [query] — a Google place whose ID Google lost.
  Future<void> searchGoogleMaps(String query) => _launch(googleSearchUri(query));

  Future<void> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Opens a stored map link verbatim (a link stop's saved Google Maps URL).
  /// The URL was allowlist-validated to a Google Maps host on save, so this
  /// opens the Google Maps app when installed and the website otherwise.
  Future<void> openUrl(String url) => _launch(Uri.parse(url));

  @visibleForTesting
  Uri placeUri(
    ExternalMapApp app, {
    required double lat,
    required double lng,
    String? label,
  }) {
    final coords = '$lat,$lng';
    final name = (label != null && label.trim().isNotEmpty) ? label.trim() : null;
    switch (app) {
      case ExternalMapApp.googleMaps:
        return Uri.https(
            'www.google.com', '/maps/search/', {'api': '1', 'query': coords});
      case ExternalMapApp.waze:
        return Uri.https('waze.com', '/ul', {'ll': coords, 'navigate': 'yes'});
      case ExternalMapApp.appleMaps:
        return Uri.https('maps.apple.com', '/', {
          'll': coords,
          // q names the dropped pin; without it Apple Maps shows raw coords.
          if (name != null) 'q': name,
        });
      case ExternalMapApp.hereWeGo:
        // Path-embedded coordinates with an optional label; ?p=yes opens the
        // installed app rather than the web preview.
        final path = name != null ? '/l/$coords,$name' : '/l/$coords';
        return Uri.https('share.here.com', path, {'p': 'yes'});
      case ExternalMapApp.yandexMaps:
        // Yandex expects longitude,latitude order (the opposite of everyone
        // else) and marks the point with pt=.
        return Uri.https('yandex.com', '/maps/',
            {'pt': '$lng,$lat', 'z': '16', 'l': 'map'});
      case ExternalMapApp.citymapper:
        // Citymapper is trip-planning first — it routes to the coordinate.
        return Uri.https('citymapper.com', '/directions', {
          'endcoord': coords,
          if (name != null) 'endname': name,
        });
      case ExternalMapApp.osmAnd:
        // OsmAnd's iOS URL scheme; only offered where it's detected.
        return Uri.parse('osmandmaps://?lat=$lat&lon=$lng&z=16'
            '${name != null ? '&title=${Uri.encodeComponent(name)}' : ''}');
      case ExternalMapApp.openStreetMap:
        // Web only (no arbitrary-coordinate app link exists); mlat/mlon drop a
        // marker, the fragment sets the initial view.
        return Uri(
          scheme: 'https',
          host: 'www.openstreetmap.org',
          path: '/',
          queryParameters: {'mlat': '$lat', 'mlon': '$lng'},
          fragment: 'map=16/$lat/$lng',
        );
      case ExternalMapApp.otherApps:
        // Standard geo: URI — Android hands it to the user's chosen map app.
        return Uri.parse(name != null
            ? 'geo:$coords?q=$coords(${Uri.encodeComponent(name)})'
            : 'geo:$coords?q=$coords');
    }
  }

  /// `query` is required by Maps URLs even with a place ID; Google reads it
  /// only if it cannot find the ID.
  @visibleForTesting
  Uri googlePlaceUri(String placeId, String query) => Uri.https(
      'www.google.com', '/maps/search/',
      {'api': '1', 'query': query, 'query_place_id': placeId});

  @visibleForTesting
  Uri googleSearchUri(String query) =>
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query});

  @visibleForTesting
  Uri routeUri(List<MapPoint> orderedPoints, {required RouteStart start}) {
    // Over the cap: keep the first stops and the destination — the start of
    // the trip is what the user navigates first.
    final cap = maxRouteStops(start);
    final points = orderedPoints.length > cap
        ? [
            ...orderedPoints.sublist(0, cap - 1),
            orderedPoints.last,
          ]
        : orderedPoints;
    final fromFirstStop = start == RouteStart.firstStop;
    final waypoints =
        points.sublist(fromFirstStop ? 1 : 0, points.length - 1);
    final origin = points.first;
    final destination = points.last;
    // waypoint_place_ids must pair one ID with each waypoint, so it is sent
    // only when every waypoint is a Google place; mixed, the text stands in.
    final allPlaces =
        waypoints.isNotEmpty && waypoints.every((p) => p.placeId != null);
    // No origin for myLocation — Google defaults it to the device location,
    // the only case where the app offers Start instead of a static preview.
    // No travelmode param — Google keeps the user's last-used mode.
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (fromFirstStop) 'origin': origin.urlText,
      if (fromFirstStop && origin.placeId != null)
        'origin_place_id': origin.placeId!,
      'destination': destination.urlText,
      if (destination.placeId != null)
        'destination_place_id': destination.placeId!,
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map((p) => p.urlText).join('|'),
      if (allPlaces)
        'waypoint_place_ids': waypoints.map((p) => p.placeId!).join('|'),
    });
  }
}
