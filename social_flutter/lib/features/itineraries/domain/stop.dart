// features/itineraries/domain/stop.dart — Stop Dart model and related enums.
//
// KEY CHANGE FROM THE OLD MODEL:
//   Before: stops had `position` (1-based integer slot within the itinerary)
//   and `parallelPosition` (0-based index within that slot).
//
//   After: stops belong to a `track` (trackId) and have a `rank` — a
//   fractional-index string that determines their order within the track.
//   No integer positions exist anywhere in the model.
//
// WHY STOPTYPE IS A PLACEHOLDER IN fromJson:
//   StopType (origin / waypoint / arrival) is derived from the stop's TRACK
//   position in the itinerary, not from the stop itself. A stop doesn't know
//   whether its track is first, last, or in the middle — only the itinerary
//   knows that after all tracks are loaded. So fromJson always sets the
//   placeholder value `StopType.waypoint`, and Itinerary._parseTracks()
//   overwrites it with the correct value after deserialization.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

enum StopType {
  origin,
  waypoint,
  arrival;
}

/// Category of a stop (user selects from a fixed list).
enum PlaceType {
  eatDrink,
  sleep,
  pray,
  learnSee,
  buy,
  playWatch,
  nature,
  transport,
  healBathe,
  entertainment,
  sight;

  // Localized display name — resolved against the active locale (en/fr).
  String label(AppLocalizations l10n) => switch (this) {
        PlaceType.eatDrink => l10n.placeTypeEatDrink,
        PlaceType.sleep => l10n.placeTypeSleep,
        PlaceType.pray => l10n.placeTypePray,
        PlaceType.learnSee => l10n.placeTypeLearnSee,
        PlaceType.buy => l10n.placeTypeBuy,
        PlaceType.playWatch => l10n.placeTypePlayWatch,
        PlaceType.nature => l10n.placeTypeNature,
        PlaceType.transport => l10n.placeTypeTransport,
        PlaceType.healBathe => l10n.placeTypeHealBathe,
        PlaceType.entertainment => l10n.placeTypeEntertainment,
        PlaceType.sight => l10n.placeTypeSight,
      };

  // Legacy DB values (stored before the camelCase rename) mapped to their
  // current enum members. fromString handles these transparently.
  static const _legacyMap = {
    'restaurant': PlaceType.eatDrink,
    'cafe': PlaceType.eatDrink,
    'museum': PlaceType.learnSee,
    'hotel': PlaceType.sleep,
    'park': PlaceType.nature,
    'station': PlaceType.transport,
    'airport': PlaceType.transport,
    'beach': PlaceType.nature,
    'landmark': PlaceType.sight,
    // Pre-rename value: stops stored 'travel' before the transport rename.
    'travel': PlaceType.transport,
    'other': null,
  };

  /// Always use this — never PlaceType.values.byName() directly.
  /// Returns null for unknown values instead of throwing.
  static PlaceType? fromString(String? value) {
    if (value == null) return null;
    if (_legacyMap.containsKey(value)) return _legacyMap[value];
    try {
      return PlaceType.values.byName(value);
    } catch (_) {
      return null;
    }
  }

  // Localized example hint shown under the label in the type picker.
  String hint(AppLocalizations l10n) => switch (this) {
        PlaceType.eatDrink => l10n.placeTypeHintEatDrink,
        PlaceType.sleep => l10n.placeTypeHintSleep,
        PlaceType.pray => l10n.placeTypeHintPray,
        PlaceType.learnSee => l10n.placeTypeHintLearnSee,
        PlaceType.buy => l10n.placeTypeHintBuy,
        PlaceType.playWatch => l10n.placeTypeHintPlayWatch,
        PlaceType.nature => l10n.placeTypeHintNature,
        PlaceType.transport => l10n.placeTypeHintTransport,
        PlaceType.healBathe => l10n.placeTypeHintHealBathe,
        PlaceType.entertainment => l10n.placeTypeHintEntertainment,
        PlaceType.sight => l10n.placeTypeHintSight,
      };

  Color get color => switch (this) {
        PlaceType.eatDrink => const Color(0xFFE65100),
        PlaceType.sleep => const Color(0xFF5E35B1),
        PlaceType.pray => const Color(0xFF00897B),
        PlaceType.learnSee => const Color(0xFF1E88E5),
        PlaceType.buy => const Color(0xFFD81B60),
        PlaceType.playWatch => const Color(0xFF43A047),
        PlaceType.nature => const Color(0xFF2E7D32),
        PlaceType.transport => const Color(0xFF546E7A),
        PlaceType.healBathe => const Color(0xFF0097A7),
        PlaceType.entertainment => const Color(0xFF6A1B9A),
        PlaceType.sight => const Color(0xFFF57F17),
      };

  IconData get icon => switch (this) {
        PlaceType.eatDrink => Icons.restaurant,
        PlaceType.sleep => Icons.hotel,
        PlaceType.pray => Icons.church,
        PlaceType.learnSee => Icons.museum,
        PlaceType.buy => Icons.shopping_bag_outlined,
        PlaceType.playWatch => Icons.sports,
        PlaceType.nature => Icons.park_outlined,
        PlaceType.transport => Icons.directions_transit,
        PlaceType.healBathe => Icons.spa_outlined,
        PlaceType.entertainment => Icons.theater_comedy_outlined,
        PlaceType.sight => Icons.photo_camera_outlined,
      };
}

class Stop {
  final String id;
  final String itineraryId;

  /// Which track (column of alternatives) this stop belongs to.
  final String trackId;

  /// Fractional-index rank — determines order within the track.
  final String rank;

  /// Role of this stop in the journey. Set to `waypoint` as a placeholder by
  /// fromJson; overwritten by Itinerary._parseTracks() with the real value.
  final StopType type;

  final String? placeName;
  final String? placeAddress;
  final double? lat;
  final double? lng;
  final PlaceType? placeType;

  final int? durationMin;
  final double cost;
  final bool isFree;

  final String? notes;
  final List<Annotation> annotations;
  final DateTime createdAt;

  const Stop({
    required this.id,
    required this.itineraryId,
    required this.trackId,
    required this.rank,
    required this.type,
    this.placeName,
    this.placeAddress,
    this.lat,
    this.lng,
    this.placeType,
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
      trackId: json['track_id'] as String,
      rank: json['rank'] as String,
      // Placeholder — Itinerary._parseTracks() assigns the real StopType.
      type: StopType.waypoint,
      placeName: json['place_name'] as String?,
      placeAddress: json['place_address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      placeType: PlaceType.fromString(json['place_type'] as String?),
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
      'track_id': trackId,
      'rank': rank,
      // StopType is NOT sent to the server — it is derived on the client.
      if (placeName != null) 'place_name': placeName,
      if (placeAddress != null) 'place_address': placeAddress,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (placeType != null) 'place_type': placeType!.name,
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
    String? trackId,
    String? rank,
    StopType? type,
    String? placeName,
    String? placeAddress,
    double? lat,
    double? lng,
    PlaceType? placeType,
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
      trackId: trackId ?? this.trackId,
      rank: rank ?? this.rank,
      type: type ?? this.type,
      placeName: placeName ?? this.placeName,
      placeAddress: placeAddress ?? this.placeAddress,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      placeType: placeType ?? this.placeType,
      durationMin: durationMin ?? this.durationMin,
      cost: cost ?? this.cost,
      isFree: isFree ?? this.isFree,
      notes: notes ?? this.notes,
      annotations: annotations ?? this.annotations,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get formattedDuration {
    if (durationMin == null || durationMin! <= 0) return '—';
    final years = durationMin! ~/ (60 * 24 * 365);
    int remainingMin = durationMin! % (60 * 24 * 365);
    final days = remainingMin ~/ (60 * 24);
    remainingMin = remainingMin % (60 * 24);
    final hours = remainingMin ~/ 60;
    final minutes = remainingMin % 60;
    String returnvalue = '';
    if (years > 0) returnvalue += '${years}y ';
    if (days > 0) returnvalue += '${days}d ';
    if (hours > 0) returnvalue += '${hours}h ';
    if (minutes > 0) returnvalue += '${minutes}min';
    return returnvalue;
  }
}
