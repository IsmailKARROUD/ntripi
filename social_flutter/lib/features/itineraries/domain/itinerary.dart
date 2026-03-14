// features/itineraries/domain/itinerary.dart — Itinerary Dart model.

import 'package:social_flutter/features/itineraries/domain/stop.dart';

/// A travel itinerary owned by a user.
///
/// The same class is used for both summary (list view) and detail (full view)
/// responses. In summary responses, [stops] is an empty list. In detail
/// responses, [stops] is populated with the full ordered stop list.
class Itinerary {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final int totalDurationMin;
  final double totalCost;
  final String currency;
  final int? safetyRating;
  final bool isPublic;
  final DateTime createdAt;

  /// Empty in summary views, populated in detail views.
  final List<Stop> stops;

  const Itinerary({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.coverImageUrl,
    required this.totalDurationMin,
    required this.totalCost,
    required this.currency,
    this.safetyRating,
    required this.isPublic,
    required this.createdAt,
    this.stops = const [],
  });

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    return Itinerary(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      totalDurationMin: json['total_duration_min'] as int? ?? 0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'EUR',
      safetyRating: json['safety_rating'] as int?,
      isPublic: json['is_public'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      stops: (json['stops'] as List<dynamic>?)
              ?.map((s) => Stop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      if (description != null) 'description': description,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      'total_duration_min': totalDurationMin,
      'total_cost': totalCost,
      'currency': currency,
      if (safetyRating != null) 'safety_rating': safetyRating,
      'is_public': isPublic,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Itinerary copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? coverImageUrl,
    int? totalDurationMin,
    double? totalCost,
    String? currency,
    int? safetyRating,
    bool? isPublic,
    DateTime? createdAt,
    List<Stop>? stops,
  }) {
    return Itinerary(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      totalDurationMin: totalDurationMin ?? this.totalDurationMin,
      totalCost: totalCost ?? this.totalCost,
      currency: currency ?? this.currency,
      safetyRating: safetyRating ?? this.safetyRating,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      stops: stops ?? this.stops,
    );
  }

  // ---------------------------------------------------------------------------
  // Helper getters
  // ---------------------------------------------------------------------------

  /// Human-readable duration: "2h 30min", "45min", or "—" if zero.
  String get formattedDuration {
    if (totalDurationMin <= 0) return '—';
    final hours = totalDurationMin ~/ 60;
    final minutes = totalDurationMin % 60;
    if (hours == 0) return '${minutes}min';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}min';
  }

  /// Human-readable cost: "52.90 EUR" or "Free" when total is 0.
  String get formattedCost {
    if (totalCost <= 0.0) return 'Free';
    return '${totalCost.toStringAsFixed(2)} $currency';
  }

  /// The origin stop, if one exists.
  Stop? get origin {
    try {
      return stops.firstWhere((s) => s.type == StopType.origin);
    } catch (_) {
      return null;
    }
  }

  /// The destination stop, if one exists.
  Stop? get destination {
    try {
      return stops.firstWhere((s) => s.type == StopType.destination);
    } catch (_) {
      return null;
    }
  }
}
