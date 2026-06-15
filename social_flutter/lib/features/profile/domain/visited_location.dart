// features/profile/domain/visited_location.dart
//
// A single stop coordinate from one of the user's itineraries, aggregated
// across all itineraries the viewer is allowed to see. Used by the profile
// hero map and the fullscreen "Where I've been" map.

class VisitedLocation {
  final double lat;
  final double lng;
  final String? placeName;
  final String? placeType;
  final String itineraryId;
  final String stopId;

  const VisitedLocation({
    required this.lat,
    required this.lng,
    this.placeName,
    this.placeType,
    required this.itineraryId,
    required this.stopId,
  });

  factory VisitedLocation.fromJson(Map<String, dynamic> json) {
    return VisitedLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      placeName: json['place_name'] as String?,
      placeType: json['place_type'] as String?,
      itineraryId: json['itinerary_id'] as String,
      stopId: json['stop_id'] as String,
    );
  }
}
