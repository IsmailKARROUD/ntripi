// features/itineraries/domain/trip_edit_answer.dart — What a trip edit answers
// when the app asks for the trip back (`?return=itinerary`).

import 'package:ntripi/features/itineraries/domain/itinerary.dart';

/// The whole trip as GET /itineraries/{id} would show it right after the save,
/// so the app adopts it instead of downloading the trip again.
class TripEditAnswer {
  const TripEditAnswer(this.itinerary, {this.createdId});

  factory TripEditAnswer.fromJson(Map<String, dynamic> json) {
    final trip = json['itinerary'];
    return TripEditAnswer(
      trip is Map<String, dynamic> ? Itinerary.fromJson(trip) : null,
      createdId: json['created_id'] as String?,
    );
  }

  /// Null only when the save itself took this viewer's access away — an
  /// editor's text hidden on the spot by moderation, which a GET answers 403.
  final Itinerary? itinerary;

  /// What a create made, which the stop form attaches its queued notes to.
  /// Null for updates and deletes.
  final String? createdId;
}
