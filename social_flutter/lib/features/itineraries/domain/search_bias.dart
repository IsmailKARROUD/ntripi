// domain/search_bias.dart — where a place search should look first.
//
// Both searches (OpenStreetMap and Google) prefer results near the trip
// itself: the alternative already in the same track, else the nearest earlier
// track's stop, else the trip's first stop with coordinates. Only a trip with
// no coordinates at all falls back to the device — rounded to 0.1° (about
// 11 km), which the Privacy Policy discloses. A bias only ranks; it never
// restricts.

import 'package:ntripi/features/itineraries/domain/track.dart';

typedef BiasPoint = ({double lat, double lng});

/// 0.1°: enough to steer a search, too coarse to place a person.
double roundForBias(double degrees) => (degrees * 10).roundToDouble() / 10;

/// The anchor for a search in the stop being added or edited.
///
/// [trackId] is the track the stop belongs to (null for a new track, which
/// [afterTrackId] or [beforeTrackId] places). [editingStopId] is excluded so a
/// stop is never its own anchor.
BiasPoint? searchBias({
  required List<Track> tracks,
  String? trackId,
  String? afterTrackId,
  String? beforeTrackId,
  String? editingStopId,
  double? deviceLat,
  double? deviceLng,
}) {
  BiasPoint? coordsIn(Track track) {
    for (final stop in track.stops) {
      if (stop.id == editingStopId) continue;
      if (stop.lat != null && stop.lng != null) {
        return (lat: stop.lat!, lng: stop.lng!);
      }
    }
    return null;
  }

  final anchorId = trackId ?? afterTrackId;
  var at = anchorId == null ? -1 : tracks.indexWhere((t) => t.id == anchorId);
  if (at < 0 && beforeTrackId != null) {
    // A new track placed before another: the nearest earlier one is its anchor.
    at = tracks.indexWhere((t) => t.id == beforeTrackId) - 1;
  }
  if (at >= 0) {
    // The same track first (an alternative to this stop), then the earlier
    // tracks, nearest first.
    for (var i = at; i >= 0; i--) {
      final found = coordsIn(tracks[i]);
      if (found != null) return found;
    }
  }
  for (final track in tracks) {
    final found = coordsIn(track);
    if (found != null) return found;
  }
  if (deviceLat != null && deviceLng != null) {
    return (lat: roundForBias(deviceLat), lng: roundForBias(deviceLng));
  }
  return null;
}
