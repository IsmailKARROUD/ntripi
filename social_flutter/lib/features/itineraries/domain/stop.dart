// features/itineraries/domain/stop.dart — Stop Dart model and related enums.

import 'package:social_flutter/features/itineraries/domain/annotation.dart';

/// The role of a stop in the itinerary.
enum StopType {
  origin,
  waypoint,
  transit,
  destination;
}

/// How the user travels on a transit stop.
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
  car;
}

/// Category of a non-transit stop (user selects from a fixed list).
/// Using our own enum instead of any third-party provider category.
enum PlaceType {
  restaurant,
  cafe,
  museum,
  hotel,
  park,
  station,
  airport,
  beach,
  landmark,
  other;
}

/// A single step in an itinerary.
class Stop {
  final String id;
  final String itineraryId;
  final int position;
  final StopType type;

  // Location — user-authored text + OSM coordinates
  final String? placeName;
  final String? placeAddress;
  final double? lat;
  final double? lng;

  // Place classification (non-transit stops)
  final PlaceType? placeType;

  // Transit-specific fields
  final TransportMode? transportMode;
  final String? transportLine;
  final String? transportDirection;

  // Time and money
  final int? durationMin;
  final double cost;
  final bool isFree;

  final String? notes;
  final List<Annotation> annotations;
  final DateTime createdAt;

  const Stop({
    required this.id,
    required this.itineraryId,
    required this.position,
    required this.type,
    this.placeName,
    this.placeAddress,
    this.lat,
    this.lng,
    this.placeType,
    this.transportMode,
    this.transportLine,
    this.transportDirection,
    this.durationMin,
    this.cost = 0.0,
    this.isFree = false,
    this.notes,
    this.annotations = const [],
    required this.createdAt,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: json['id'] as String,
      itineraryId: json['itinerary_id'] as String,
      position: json['position'] as int,
      type: StopType.values.byName(json['type'] as String),
      placeName: json['place_name'] as String?,
      placeAddress: json['place_address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      placeType: json['place_type'] != null
          ? PlaceType.values.byName(json['place_type'] as String)
          : null,
      transportMode: json['transport_mode'] != null
          ? TransportMode.values.byName(json['transport_mode'] as String)
          : null,
      transportLine: json['transport_line'] as String?,
      transportDirection: json['transport_direction'] as String?,
      durationMin: json['duration_min'] as int?,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      isFree: json['is_free'] as bool? ?? false,
      notes: json['notes'] as String?,
      annotations: (json['annotations'] as List<dynamic>?)
              ?.map((a) => Annotation.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itinerary_id': itineraryId,
      'position': position,
      'type': type.name,
      if (placeName != null) 'place_name': placeName,
      if (placeAddress != null) 'place_address': placeAddress,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (placeType != null) 'place_type': placeType!.name,
      if (transportMode != null) 'transport_mode': transportMode!.name,
      if (transportLine != null) 'transport_line': transportLine,
      if (transportDirection != null) 'transport_direction': transportDirection,
      if (durationMin != null) 'duration_min': durationMin,
      'cost': cost,
      'is_free': isFree,
      if (notes != null) 'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Stop copyWith({
    String? id,
    String? itineraryId,
    int? position,
    StopType? type,
    String? placeName,
    String? placeAddress,
    double? lat,
    double? lng,
    PlaceType? placeType,
    TransportMode? transportMode,
    String? transportLine,
    String? transportDirection,
    int? durationMin,
    double? cost,
    bool? isFree,
    String? notes,
    List<Annotation>? annotations,
    DateTime? createdAt,
  }) {
    return Stop(
      id: id ?? this.id,
      itineraryId: itineraryId ?? this.itineraryId,
      position: position ?? this.position,
      type: type ?? this.type,
      placeName: placeName ?? this.placeName,
      placeAddress: placeAddress ?? this.placeAddress,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      placeType: placeType ?? this.placeType,
      transportMode: transportMode ?? this.transportMode,
      transportLine: transportLine ?? this.transportLine,
      transportDirection: transportDirection ?? this.transportDirection,
      durationMin: durationMin ?? this.durationMin,
      cost: cost ?? this.cost,
      isFree: isFree ?? this.isFree,
      notes: notes ?? this.notes,
      annotations: annotations ?? this.annotations,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
