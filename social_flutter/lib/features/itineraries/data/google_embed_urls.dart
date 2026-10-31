// data/google_embed_urls.dart — the one builder of a Google map's address.
//
// Every Google map in the app (the stop page, the form's preview, the trip's
// route) is a page on our own server — routers/embed.py — that frames Google's
// free Maps Embed API with the server's key. The app never holds that key and
// never builds a google.com/maps/embed URL itself; a phone's WebView loads
// these pages and the web app frames them. One builder, so the parameters the
// server validates are written in one place
// (test/google_embed_source_guard_test.dart holds the rest of lib/ to it).

import 'package:flutter/widgets.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/domain/map_point.dart';
import 'package:ntripi/shared/data/app_locales.dart';

abstract final class GoogleEmbed {
  /// Origin + 20 waypoints + destination: Google's directions limit.
  static const maxRoutePoints = 22;

  /// One point on a map: a place by its ID, or a pin at coordinates.
  static Uri point(MapPoint point, String language) => switch (point) {
        PlacePoint(:final placeId) => _page('place', {'id': placeId}, language),
        CoordPoint(:final lat, :final lng) =>
          _page('point', {'lat': '$lat', 'lng': '$lng'}, language),
      };

  /// A text query — only the stop page's fetched link preview uses it, for a
  /// link it could name but not place.
  static Uri search(String query, String language) =>
      _page('search', {'q': query}, language);

  /// [points] as a route can carry them: past [maxRoutePoints], the start of
  /// the trip and its destination — the first stops and the last, as the route
  /// link keeps them.
  static List<MapPoint> capRoute(List<MapPoint> points) =>
      points.length > maxRoutePoints
          ? [...points.take(maxRoutePoints - 1), points.last]
          : points;

  /// The route through [points] (2 to [maxRoutePoints]); Google picks the
  /// travel mode.
  static Uri directions(List<MapPoint> points, String language) {
    assert(points.length >= 2 && points.length <= maxRoutePoints);
    return _page(
        'directions', {'points': points.map((p) => p.embedToken).join('|')}, language);
  }

  /// The map's language: the app's, when the server knows it.
  static String languageOf(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode;
    return code != null && kAppLocaleCodes.contains(code) ? code : 'en';
  }

  // `language`, never `lang`: the server's language cookie reads `lang`.
  static Uri _page(String mode, Map<String, String> query, String language) =>
      Uri.parse('$kApiBaseUrl/embed/$mode')
          .replace(queryParameters: {...query, 'language': language});
}
