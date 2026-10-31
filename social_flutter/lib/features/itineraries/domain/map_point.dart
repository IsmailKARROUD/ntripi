// domain/map_point.dart — a stop as Google's map, route and links read it.
//
// A Google place is located by its place ID; everything else by coordinates.
// Read straight from what a stop stores — and, for a link stop, from the
// link's own text (google_maps_links.dart): never fetched, never stored.

import 'package:ntripi/features/itineraries/data/google_maps_links.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';

sealed class MapPoint {
  const MapPoint();

  /// The point as the /embed page reads it: `place_id:<id>` or `lat,lng`.
  String get embedToken;

  /// The text a Maps URL needs beside an optional place ID: coordinates, or
  /// the words that find the place when the ID does not.
  String get urlText;

  /// Google's place ID, when the point has one.
  String? get placeId;
}

class PlacePoint extends MapPoint {
  @override
  final String placeId;

  /// The user's search text, else the stop's name — Maps URLs require a text
  /// query and fall back to it only if Google cannot find the ID.
  final String fallbackText;

  const PlacePoint(this.placeId, this.fallbackText);

  @override
  String get embedToken => 'place_id:$placeId';

  @override
  String get urlText => fallbackText;

  @override
  bool operator ==(Object other) =>
      other is PlacePoint &&
      other.placeId == placeId &&
      other.fallbackText == fallbackText;

  @override
  int get hashCode => Object.hash(placeId, fallbackText);
}

class CoordPoint extends MapPoint {
  final double lat;
  final double lng;

  const CoordPoint(this.lat, this.lng);

  @override
  String get embedToken => '$lat,$lng';

  @override
  String get urlText => '$lat,$lng';

  @override
  String? get placeId => null;

  @override
  bool operator ==(Object other) =>
      other is CoordPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// Where Google can find [stop], or null when nothing locates it — a short
/// link (it names no place) or a Google place Google has lost.
MapPoint? mapPointOf(Stop stop) {
  final fallback = (stop.googlePlaceQuery?.trim().isNotEmpty ?? false)
      ? stop.googlePlaceQuery!.trim()
      : (stop.placeName?.trim() ?? '');
  if (stop.hasLiveGooglePlace) return PlacePoint(stop.googlePlaceId!, fallback);
  if (stop.googlePlaceMissing) return null;
  if (stop.lat != null && stop.lng != null) return CoordPoint(stop.lat!, stop.lng!);
  final link = stop.mapUrl;
  if (link == null) return null;
  final placeId = extractPlaceId(link);
  if (placeId != null) return PlacePoint(placeId, fallback);
  final coords = extractMapCoords(link);
  return coords == null ? null : CoordPoint(coords.$1, coords.$2);
}
