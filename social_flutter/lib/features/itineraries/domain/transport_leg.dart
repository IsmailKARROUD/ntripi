// features/itineraries/domain/transport_leg.dart — TransportLeg model and TransportMode enum.
//
// TransportMode drives the icon and label shown throughout the UI.
// position is 1-based and is assigned server-side; when building legs locally
// in SegmentFormScreen, a placeholder id ('local-N') is used for display only.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';

enum TransportMode {
  walk,
  bus,
  tram,
  metro,
  train,
  taxi,
  uber,
  bike,
  ferry,
  car,
  airplane;

  String get label => const {
        TransportMode.walk: 'Walk',
        TransportMode.bus: 'Bus',
        TransportMode.tram: 'Tram',
        TransportMode.metro: 'Metro',
        TransportMode.train: 'Train',
        TransportMode.taxi: 'Taxi',
        TransportMode.uber: 'Uber',
        TransportMode.bike: 'Bike',
        TransportMode.ferry: 'Ferry',
        TransportMode.car: 'Car',
        TransportMode.airplane: 'Airplane',
      }[this]!;

  IconData get icon => const {
        TransportMode.walk: Icons.directions_walk,
        TransportMode.bus: Icons.directions_bus,
        TransportMode.tram: Icons.tram,
        TransportMode.metro: Icons.subway,
        TransportMode.train: Icons.train,
        TransportMode.taxi: Icons.local_taxi,
        TransportMode.uber: Icons.directions_car,
        TransportMode.bike: Icons.directions_bike,
        TransportMode.ferry: Icons.directions_boat,
        TransportMode.airplane: Icons.flight,
        TransportMode.car: Icons.directions_car,
      }[this]!;
}

class TransportLeg {
  final String id;
  final String segmentId;
  final int position;
  final TransportMode mode;
  final String? line;
  final String? direction;
  final int? durationMin;
  final double cost;
  final bool isFree;
  final String? notes;
  final AnnotationType? noteType;
  final DateTime createdAt;

  const TransportLeg({
    required this.id,
    required this.segmentId,
    required this.position,
    required this.mode,
    this.line,
    this.direction,
    this.durationMin,
    this.cost = 0.0,
    this.isFree = false,
    this.notes,
    this.noteType,
    required this.createdAt,
  });

  factory TransportLeg.fromJson(Map<String, dynamic> json) {
    final rawNoteType = json['note_type'] as String?;
    return TransportLeg(
      id: json['id'] as String,
      segmentId: json['segment_id'] as String,
      position: json['position'] as int,
      mode: TransportMode.values.byName(json['mode'] as String),
      line: json['line'] as String?,
      direction: json['direction'] as String?,
      durationMin: json['duration_min'] as int?,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      isFree: json['is_free'] as bool? ?? false,
      notes: json['notes'] as String?,
      noteType: rawNoteType != null
          ? AnnotationType.values.byName(rawNoteType)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'segment_id': segmentId,
        'position': position,
        'mode': mode.name,
        if (line != null) 'line': line,
        if (direction != null) 'direction': direction,
        if (durationMin != null) 'duration_min': durationMin,
        'cost': cost,
        'is_free': isFree,
        if (notes != null) 'notes': notes,
        if (noteType != null) 'note_type': noteType!.name,
        'created_at': createdAt.toIso8601String(),
      };

  TransportLeg copyWith({
    String? id,
    String? segmentId,
    int? position,
    TransportMode? mode,
    String? line,
    String? direction,
    int? durationMin,
    double? cost,
    bool? isFree,
    String? notes,
    AnnotationType? noteType,
    DateTime? createdAt,
  }) {
    return TransportLeg(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      position: position ?? this.position,
      mode: mode ?? this.mode,
      line: line ?? this.line,
      direction: direction ?? this.direction,
      durationMin: durationMin ?? this.durationMin,
      cost: cost ?? this.cost,
      isFree: isFree ?? this.isFree,
      notes: notes ?? this.notes,
      noteType: noteType ?? this.noteType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get formattedDuration {
    final d = durationMin;
    if (d == null || d <= 0) return '';
    final years = d ~/ (60 * 24 * 365);
    var remaining = d % (60 * 24 * 365);
    final days = remaining ~/ (60 * 24);
    remaining = remaining % (60 * 24);
    final hours = remaining ~/ 60;
    final minutes = remaining % 60;
    final parts = <String>[
      if (years > 0) '${years}y',
      if (days > 0) '${days}d',
      if (hours > 0) '${hours}h',
      if (minutes > 0) '${minutes}min',
    ];
    return parts.join(' ');
  }

  /// Compact one-line summary: "Metro · Line 9 → direction Nation"
  String get summary {
    final parts = <String>[
      mode.label,
      if (line != null && line!.isNotEmpty) line!,
      if (direction != null && direction!.isNotEmpty) '→ $direction',
    ];
    return parts.join(' ');
  }
}
