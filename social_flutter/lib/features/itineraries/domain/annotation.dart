// features/itineraries/domain/annotation.dart — Annotation Dart model.

/// The four types of annotation a user can attach to a stop.
enum AnnotationType {
  advice,   // Helpful tip
  caution,  // Something to be aware of
  avoid,    // Something to skip
  info;     // Neutral information
}

/// A user-written note attached to a stop.
class Annotation {
  final String id;
  final String stopId;
  final AnnotationType type;
  final String content;
  final DateTime createdAt;

  const Annotation({
    required this.id,
    required this.stopId,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  factory Annotation.fromJson(Map<String, dynamic> json) {
    return Annotation(
      id: json['id'] as String,
      stopId: json['stop_id'] as String,
      type: AnnotationType.values.byName(json['type'] as String),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stop_id': stopId,
      'type': type.name,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
