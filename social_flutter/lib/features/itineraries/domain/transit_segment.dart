// features/itineraries/domain/transit_segment.dart — TransitSegment model.

import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

class TransitSegment {
  final String id;
  final String itineraryId;
  final String fromStopId;
  final String toStopId;
  final int totalDurationMin;
  final double totalCost;
  final List<TransportLeg> legs;
  final DateTime createdAt;

  const TransitSegment({
    required this.id,
    required this.itineraryId,
    required this.fromStopId,
    required this.toStopId,
    required this.totalDurationMin,
    required this.totalCost,
    this.legs = const [],
    required this.createdAt,
  });

  factory TransitSegment.fromJson(Map<String, dynamic> json) {
    return TransitSegment(
      id: json['id'] as String,
      itineraryId: json['itinerary_id'] as String,
      fromStopId: json['from_stop_id'] as String,
      toStopId: json['to_stop_id'] as String,
      totalDurationMin: json['total_duration_min'] as int? ?? 0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
      legs: (json['legs'] as List<dynamic>?)
              ?.map((l) => TransportLeg.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  TransitSegment copyWith({
    String? id,
    String? itineraryId,
    String? fromStopId,
    String? toStopId,
    int? totalDurationMin,
    double? totalCost,
    List<TransportLeg>? legs,
    DateTime? createdAt,
  }) {
    return TransitSegment(
      id: id ?? this.id,
      itineraryId: itineraryId ?? this.itineraryId,
      fromStopId: fromStopId ?? this.fromStopId,
      toStopId: toStopId ?? this.toStopId,
      totalDurationMin: totalDurationMin ?? this.totalDurationMin,
      totalCost: totalCost ?? this.totalCost,
      legs: legs ?? this.legs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// All leg summaries joined with "·" separator.
  String get summary {
    if (legs.isEmpty) return '—';
    return legs.map((l) => l.summary).join(' · ');
  }

  String get formattedDuration {
    if (totalDurationMin <= 0) return '—';
    final h = totalDurationMin ~/ 60;
    final m = totalDurationMin % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  String formattedCost(String currency) {
    if (totalCost <= 0.0) return 'Free';
    return '${totalCost.toStringAsFixed(2)} $currency';
  }
}
