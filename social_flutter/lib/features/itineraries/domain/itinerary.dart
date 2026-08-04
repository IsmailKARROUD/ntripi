// features/itineraries/domain/itinerary.dart — Itinerary Dart model.

import 'package:social_flutter/shared/models/moderation_status.dart';
import 'package:flutter/material.dart';
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/utils/duration_format.dart';

/// Four-level visibility for an itinerary.
enum ItineraryVisibility {
  public,
  followers,
  restricted,
  onlyMe;

  String label(AppLocalizations l10n) => switch (this) {
        public => l10n.visibilityPublic,
        followers => l10n.visibilityFollowers,
        restricted => l10n.visibilityRestricted,
        onlyMe => l10n.visibilityOnlyMe,
      };

  String description(AppLocalizations l10n) => switch (this) {
        public => l10n.visibilityPublicDesc,
        followers => l10n.visibilityFollowersDesc,
        restricted => l10n.visibilityRestrictedDesc,
        onlyMe => l10n.visibilityOnlyMeDesc,
      };

  IconData get icon => switch (this) {
        public => Icons.public,
        followers => Icons.people,
        restricted => Icons.lock_outline,
        onlyMe => Icons.lock,
      };
}

/// A travel itinerary owned by a user.
///
/// In summary responses [tracks] is empty. In detail responses it is populated
/// with the full ordered track/stop structure.
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
  final DateTime updatedAt;

  /// Community rating aggregate. Null until at least one rating exists.
  final double? ratingAvg;
  final int ratingCount;

  /// Ordered tracks. Empty in summary views, populated in detail views.
  final List<Track> tracks;

  /// Transit segments. Empty in summary views.
  final List<TransitSegment> segments;

  /// Itinerary-level annotations. Empty in summary views.
  final List<ItineraryAnnotation> annotations;

  /// Count of stops across all tracks. Populated from stops_count in summary
  /// responses, or derived from [tracks] in detail responses.
  final int stopsCount;

  /// True when a moderator hid this itinerary: it stays visible to its author
  /// (who sees a banner) but to nobody else. The server only ever sends true to
  /// the owner — everyone else is filtered out or denied before the response.
  final bool hidden;

  /// Combined moderation state of this itinerary's text and cover image.
  /// Unknown values from a newer backend degrade to [ModerationStatus.approved]
  /// so a server-side addition can never break a deployed client.
  final ModerationStatus moderationStatus;

  /// The owner's "best time to visit". Null when they never set one — and
  /// always null in summary views, which do not carry the fields at all.
  final RecommendedPeriod? recommendedPeriod;

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
    required this.updatedAt,
    this.ratingAvg,
    this.ratingCount = 0,
    this.tracks = const [],
    this.segments = const [],
    this.annotations = const [],
    this.stopsCount = 0,
    this.hidden = false,
    this.moderationStatus = ModerationStatus.approved,
    this.recommendedPeriod,
  });

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    final tracks = _parseTracks(json['tracks'] as List<dynamic>?);
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
      updatedAt: DateTime.parse(json['updated_at'] as String),
      ratingAvg: (json['rating_avg'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int? ?? 0,
      tracks: tracks,
      segments: (json['segments'] as List<dynamic>?)
              ?.map((s) => TransitSegment.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      annotations: (json['annotations'] as List<dynamic>?)
              ?.map((a) =>
                  ItineraryAnnotation.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      stopsCount: tracks.isNotEmpty
          ? tracks.fold(0, (sum, t) => sum + t.stops.length)
          : (json['stops_count'] as int? ?? 0),
      // Absent from summary/list payloads — only the detail response carries it.
      hidden: json['hidden'] as bool? ?? false,
      moderationStatus: ModerationStatus.fromString(
        json['moderation_status'] as String?,
      ),
      // Detail-only, like `hidden` — summary payloads never carry these keys,
      // so this stays null there rather than becoming an empty period.
      recommendedPeriod: RecommendedPeriod.fromItineraryJson(json),
    );
  }

  /// Assign the correct StopType to every stop based on its track's position
  /// in the overall list.
  ///
  /// WHY THIS IS DONE HERE AND NOT IN Stop.fromJson:
  ///   A stop doesn't know whether its track is the first or last — only the
  ///   itinerary knows that. So Stop.fromJson sets a placeholder (waypoint)
  ///   and this method overwrites it with the real value after all tracks are
  ///   loaded.
  ///
  /// Rules:
  ///   0 tracks  → nothing to do (empty itinerary)
  ///   1 track   → all stops in it are StopType.origin (it is both origin AND arrival)
  ///   2+ tracks → first track = origin, last track = arrival, rest = waypoint
  ///
  /// The server pre-sorts both tracks (by rank) and stops within each track
  /// (by rank) before returning them, so we trust that order here.
  static List<Track> _parseTracks(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];

    final tracks = raw
        .map((t) => Track.fromJson(t as Map<String, dynamic>))
        .toList();

    if (tracks.isEmpty) return tracks;

    StopType typeForTrackIndex(int idx) {
      if (tracks.length == 1) return StopType.origin;
      if (idx == 0) return StopType.origin;
      if (idx == tracks.length - 1) return StopType.arrival;
      return StopType.waypoint;
    }

    return [
      for (var i = 0; i < tracks.length; i++)
        tracks[i].copyWith(
          stops: [
            for (final stop in tracks[i].stops)
              stop.copyWith(type: typeForTrackIndex(i))
          ],
        ),
    ];
  }

  /// Flat list of all stops across all tracks (for legacy helpers / display).
  List<Stop> get stops => tracks.expand((t) => t.stops).toList();

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
      'updated_at': updatedAt.toIso8601String(),
      'hidden': hidden,
      'moderation_status': moderationStatus.wireValue,
      if (recommendedPeriod != null) ...recommendedPeriod!.toPayload(),
    };
  }

  Itinerary copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    // Explicit clear — the `??` fallback below can't null a field, only replace it.
    bool clearDescription = false,
    String? coverImageUrl,
    // Explicit clear — the `??` fallback below can't null a field, only replace it.
    bool clearCoverImageUrl = false,
    int? totalDurationMin,
    double? totalCost,
    String? currency,
    ItineraryVisibility? visibility,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? ratingAvg,
    int? ratingCount,
    List<Track>? tracks,
    List<TransitSegment>? segments,
    List<ItineraryAnnotation>? annotations,
    int? stopsCount,
    bool? hidden,
    ModerationStatus? moderationStatus,
    RecommendedPeriod? recommendedPeriod,
    // Explicit clear — the `??` fallback below can't null a field, only replace it.
    bool clearRecommendedPeriod = false,
  }) {
    return Itinerary(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      coverImageUrl:
          clearCoverImageUrl ? null : (coverImageUrl ?? this.coverImageUrl),
      totalDurationMin: totalDurationMin ?? this.totalDurationMin,
      totalCost: totalCost ?? this.totalCost,
      currency: currency ?? this.currency,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      tracks: tracks ?? this.tracks,
      segments: segments ?? this.segments,
      annotations: annotations ?? this.annotations,
      stopsCount: stopsCount ?? this.stopsCount,
      hidden: hidden ?? this.hidden,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      recommendedPeriod: clearRecommendedPeriod
          ? null
          : (recommendedPeriod ?? this.recommendedPeriod),
    );
  }

  // ---------------------------------------------------------------------------
  // Visibility helpers
  // ---------------------------------------------------------------------------

  String visibilityLabel(AppLocalizations l10n) => visibility.label(l10n);

  IconData get visibilityIcon => visibility.icon;

  // ---------------------------------------------------------------------------
  // Duration / cost helpers
  // ---------------------------------------------------------------------------

  String formattedDuration(AppLocalizations l10n) =>
      formatDuration(totalDurationMin, l10n);

  String formattedCost(AppLocalizations l10n) {
    if (totalCost <= 0.0) return l10n.freeLegLabel;
    return formatMoney(totalCost, currency);
  }

  /// The origin stop (first stop in the first track), if any.
  Stop? get origin {
    try {
      return stops.firstWhere((s) => s.type == StopType.origin);
    } catch (_) {
      return null;
    }
  }

  /// The arrival stop (first stop in the last track), if any.
  Stop? get arrival {
    try {
      return stops.firstWhere((s) => s.type == StopType.arrival);
    } catch (_) {
      return null;
    }
  }

  /// ETag value for use in If-Match mutation headers (RFC 7232 — quotes required).
  ///
  /// The server computes the same value from itinerary.updated_at. On PostgreSQL
  /// this produces "+00:00" timezone; Dart's toIso8601String() on a UTC DateTime
  /// produces "Z". The server normalizes both forms before comparing, so either
  /// format is accepted. See _normalize_etag() in app/dependencies.py.
  String get eTag => '"${updatedAt.toIso8601String()}"';
}
