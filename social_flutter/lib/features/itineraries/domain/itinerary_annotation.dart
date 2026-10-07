// features/itineraries/domain/itinerary_annotation.dart — Itinerary-level annotation model.

import 'package:social_flutter/features/itineraries/domain/annotation.dart';

/// A user-written note attached to an itinerary (not to a stop).
class ItineraryAnnotation {
  final String id;
  final String itineraryId;
  final AnnotationType type;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Language the server detected for this text (ISO 639-1), or null when
  /// it could not tell — decides whether "See translation" is offered.
  final String? sourceLang;

  const ItineraryAnnotation({
    required this.id,
    required this.itineraryId,
    required this.type,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.sourceLang,
  });

  factory ItineraryAnnotation.fromJson(Map<String, dynamic> json) {
    return ItineraryAnnotation(
      id: json['id'] as String,
      itineraryId: json['itinerary_id'] as String,
      type: AnnotationType.fromString(json['type'] as String?),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      sourceLang: json['source_lang'] as String?,
    );
  }

  ItineraryAnnotation copyWith({
    AnnotationType? type,
    String? content,
    DateTime? updatedAt,
  }) {
    return ItineraryAnnotation(
      id: id,
      itineraryId: itineraryId,
      type: type ?? this.type,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceLang: sourceLang,
    );
  }
}
