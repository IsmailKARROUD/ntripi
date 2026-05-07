// features/itineraries/domain/track.dart — Track Dart model.
//
// A track groups parallel stop alternatives at the same point in a journey.
// Tracks are ordered by their fractional-index rank string; stops within a
// track are also ordered by rank.
//
// StopType is derived from track position in Itinerary._parseTracks(), not
// stored here. Stop.fromJson always sets a placeholder of StopType.waypoint.

import 'package:social_flutter/features/itineraries/domain/stop.dart';

class Track {
  final String id;
  final String itineraryId;
  final String rank;
  final List<Stop> stops;

  const Track({
    required this.id,
    required this.itineraryId,
    required this.rank,
    this.stops = const [],
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      itineraryId: json['itinerary_id'] as String,
      rank: json['rank'] as String,
      stops: (json['stops'] as List<dynamic>?)
              ?.map((s) => Stop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itinerary_id': itineraryId,
      'rank': rank,
      'stops': stops.map((s) => s.toJson()).toList(),
    };
  }

  Track copyWith({
    String? id,
    String? itineraryId,
    String? rank,
    List<Stop>? stops,
  }) {
    return Track(
      id: id ?? this.id,
      itineraryId: itineraryId ?? this.itineraryId,
      rank: rank ?? this.rank,
      stops: stops ?? this.stops,
    );
  }
}
