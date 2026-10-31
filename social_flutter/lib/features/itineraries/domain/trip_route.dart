// domain/trip_route.dart — the trip as one route: a point per track.
//
// Stops within a track are parallel alternatives, so the route takes the one
// on screen (the user's swipe), as the Google Maps route link always has. The
// trip page's route map and the route link both read this, so they can never
// draw different trips.

import 'package:ntripi/features/itineraries/domain/map_point.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';

class TripRoute {
  final List<MapPoint> points;

  /// Tracks whose stop on screen nothing locates (a short link, a lost Google
  /// place): left out of the route, and counted so the map can say so.
  final int unmapped;

  const TripRoute(this.points, this.unmapped);
}

TripRoute tripRoute(List<Track> tracks, Map<String, int> activeAlternative) {
  final points = <MapPoint>[];
  var unmapped = 0;
  for (final track in tracks) {
    if (track.stops.isEmpty) continue;
    final index =
        (activeAlternative[track.id] ?? 0).clamp(0, track.stops.length - 1);
    final point = mapPointOf(track.stops[index]);
    if (point == null) {
      unmapped++;
    } else {
      points.add(point);
    }
  }
  return TripRoute(points, unmapped);
}
