// features/itineraries/domain/track.dart — Track Dart model.
//
// WHAT IS A TRACK?
//   A track is a vertical column of parallel stop alternatives at the same
//   point in a journey. For example, at night 2 the user might have two hotel
//   options — "Hotel A" or "Hotel B". Both live in the same track.
//
// HOW TRACKS ARE ORDERED:
//   Each track has a `rank` — a short string like "a0", "b", "aV". Tracks are
//   displayed in ascending lexicographic order of rank. The rank is computed
//   server-side using fractional indexing (services/ordering.py) so inserting
//   a new track between two existing ones never requires updating other tracks.
//
// STOP TYPE DERIVATION:
//   The track's position in the list determines the StopType of its stops:
//     - First track  → StopType.origin
//     - Last track   → StopType.arrival
//     - All others   → StopType.waypoint
//   This assignment happens in Itinerary._parseTracks(), not here.

import 'package:social_flutter/features/itineraries/domain/stop.dart';

class Track {
  /// Maximum number of parallel stops allowed per track.
  ///
  /// Used by every UI affordance that gates on track capacity (the
  /// add-parallel button, the move-to-track sheet picker, and the move
  /// button's visibility predicate). Changing this number — should the UX
  /// ever support more parallels — only requires updating this constant.
  static const int maxParallelStops = 4;

  final String id;
  final String itineraryId;

  /// Fractional-index rank string — tracks are displayed sorted by this value.
  final String rank;

  /// Stops within this track, sorted by their own rank (ascending).
  /// The server pre-sorts stops before returning them, so this list is already
  /// in display order when deserialized.
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
