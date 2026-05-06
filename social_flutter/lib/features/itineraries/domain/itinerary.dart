// features/itineraries/domain/itinerary.dart — Itinerary Dart model.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';

/// Four-level visibility for an itinerary.
enum ItineraryVisibility { public, followers, restricted, onlyMe }

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
  final ItineraryVisibility visibility;
  final DateTime createdAt;

  /// Community rating aggregate. Null until at least one rating exists.
  final double? ratingAvg;
  final int ratingCount;

  /// Empty in summary views, populated in detail views.
  final List<Stop> stops;

  /// Empty in summary views, populated in detail views.
  final List<TransitSegment> segments;

  /// Itinerary-level annotations. Empty in summary views.
  final List<ItineraryAnnotation> annotations;

  /// Count of stops. Populated from `stops_count` in summary responses,
  /// or derived from [stops] in detail responses.
  final int stopsCount;

  const Itinerary({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.coverImageUrl,
    required this.totalDurationMin,
    required this.totalCost,
    required this.currency,
    required this.visibility,
    required this.createdAt,
    this.ratingAvg,
    this.ratingCount = 0,
    this.stops = const [],
    this.segments = const [],
    this.annotations = const [],
    this.stopsCount = 0,
  });

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    final stops = _parseStops(json['stops'] as List<dynamic>?);
    return Itinerary(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      totalDurationMin: json['total_duration_min'] as int? ?? 0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'EUR',
      visibility: _parseVisibility(json['visibility'] as String? ?? 'only_me'),
      createdAt: DateTime.parse(json['created_at'] as String),
      ratingAvg: (json['rating_avg'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int? ?? 0,
      stops: stops,
      segments: (json['segments'] as List<dynamic>?)
              ?.map((s) => TransitSegment.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      annotations: (json['annotations'] as List<dynamic>?)
              ?.map((a) =>
                  ItineraryAnnotation.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      stopsCount: (json['stops'] as List<dynamic>?)?.length ??
          (json['stops_count'] as int? ?? 0),
    );
  }

  static List<Stop> _parseStops(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final stops = raw
        .map((s) => Stop.fromJson(s as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        final posCmp = a.position.compareTo(b.position);
        return posCmp != 0 ? posCmp : a.parallelPosition.compareTo(b.parallelPosition);
      });

    // Group by position to determine StopType per group.
    final positions = stops.map((s) => s.position).toSet().toList()..sort();
    StopType typeFor(int pos) {
      if (pos == positions.first) return StopType.origin;
      if (pos == positions.last) return StopType.arrival;
      return StopType.waypoint;
    }

    return [for (final s in stops) s.copyWith(type: typeFor(s.position))];
  }

  /// Stops grouped by position, sorted by position then parallel_position.
  /// Each inner list contains 1–3 parallel alternatives at the same position.
  List<List<Stop>> get stopGroups {
    if (stops.isEmpty) return const [];
    final Map<int, List<Stop>> byPos = {};
    for (final s in stops) {
      byPos.putIfAbsent(s.position, () => []).add(s);
    }
    final sortedPositions = byPos.keys.toList()..sort();
    return [for (final pos in sortedPositions) byPos[pos]!];
  }

  static ItineraryVisibility _parseVisibility(String raw) {
    const map = {
      'public': ItineraryVisibility.public,
      'followers': ItineraryVisibility.followers,
      'restricted': ItineraryVisibility.restricted,
      'only_me': ItineraryVisibility.onlyMe,
    };
    return map[raw] ?? ItineraryVisibility.onlyMe;
  }

  Map<String, dynamic> toJson() {
    const reverseMap = {
      ItineraryVisibility.public: 'public',
      ItineraryVisibility.followers: 'followers',
      ItineraryVisibility.restricted: 'restricted',
      ItineraryVisibility.onlyMe: 'only_me',
    };
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      if (description != null) 'description': description,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      'total_duration_min': totalDurationMin,
      'total_cost': totalCost,
      'currency': currency,
      'visibility': reverseMap[visibility],
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
    ItineraryVisibility? visibility,
    DateTime? createdAt,
    double? ratingAvg,
    int? ratingCount,
    List<Stop>? stops,
    List<TransitSegment>? segments,
    List<ItineraryAnnotation>? annotations,
    int? stopsCount,
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
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      stops: stops ?? this.stops,
      segments: segments ?? this.segments,
      annotations: annotations ?? this.annotations,
      stopsCount: stopsCount ?? this.stopsCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Visibility helpers
  // ---------------------------------------------------------------------------

  /// Human-readable label for the current visibility level.
  String get visibilityLabel => switch (visibility) {
        ItineraryVisibility.public => 'Public',
        ItineraryVisibility.followers => 'Followers',
        ItineraryVisibility.restricted => 'Restricted',
        ItineraryVisibility.onlyMe => 'Only Me',
      };

  /// Icon representing the current visibility level.
  IconData get visibilityIcon => switch (visibility) {
        ItineraryVisibility.public => Icons.public,
        ItineraryVisibility.followers => Icons.people,
        ItineraryVisibility.restricted => Icons.lock_outline,
        ItineraryVisibility.onlyMe => Icons.lock,
      };

  // ---------------------------------------------------------------------------
  // Duration / cost helpers
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

  /// The arrival stop, if one exists.
  Stop? get arrival {
    try {
      return stops.firstWhere((s) => s.type == StopType.arrival);
    } catch (_) {
      return null;
    }
  }
}
