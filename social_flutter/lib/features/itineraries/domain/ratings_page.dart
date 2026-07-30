// features/itineraries/domain/ratings_page.dart
// Domain models for the GET /itineraries/{id}/ratings response.

import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Identity of someone who rated an itinerary.
///
/// [isDeleted] is the ONLY reliable signal that a user deleted their account.
/// Never check by username or displayName — those can be null for non-deleted
/// users (optional profile fields).
class RaterInfo {
  final String? userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const RaterInfo({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  /// True when the user deleted their account and the rating was anonymized.
  bool get isDeleted => userId == null;

  /// Safe name to display regardless of deletion state.
  String displayNameOrFallback(AppLocalizations l10n) {
    if (isDeleted) return l10n.deletedUser;
    return displayName ?? username ?? l10n.unknownUser;
  }

  factory RaterInfo.fromJson(Map<String, dynamic> json) => RaterInfo(
        userId: json['user_id'] as String?,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
      };
}

/// One rating entry with rater identity and submission time.
class RatingWithUser {
  final int score;
  final int? scoreSafety;
  final int? scoreExperience;
  final int? scoreAccessibility;
  final int? scoreFamilyFriendly;
  final int? scoreCrowdedness;

  /// Optional Markdown-source review note left by the rater.
  final String? note;

  final DateTime updatedAt;
  final RaterInfo user;

  /// The rating's own id, so a reader can report this individual review.
  /// Nullable: a cached response from before the field existed has none, and
  /// the report action is simply hidden for those.
  final String? id;

  const RatingWithUser({
    required this.score,
    this.scoreSafety,
    this.scoreExperience,
    this.scoreAccessibility,
    this.scoreFamilyFriendly,
    this.scoreCrowdedness,
    this.note,
    required this.updatedAt,
    required this.user,
    this.id,
  });

  /// Returns the score for the given dimension, or null if not rated.
  int? scoreForDimension(DimensionKey dim) => switch (dim) {
        DimensionKey.overall => score,
        DimensionKey.safety => scoreSafety,
        DimensionKey.experience => scoreExperience,
        DimensionKey.accessibility => scoreAccessibility,
        DimensionKey.familyFriendly => scoreFamilyFriendly,
        DimensionKey.crowdedness => scoreCrowdedness,
      };

  /// Human-readable relative time — e.g. "3d ago", "2mo ago", "Just now".
  String timeAgo(AppLocalizations l10n) {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inDays > 30) return l10n.timeAgoMonths((diff.inDays / 30).floor());
    if (diff.inDays > 0) return l10n.timeAgoDays(diff.inDays);
    if (diff.inHours > 0) return l10n.timeAgoHours(diff.inHours);
    if (diff.inMinutes > 0) return l10n.timeAgoMinutes(diff.inMinutes);
    return l10n.timeJustNow;
  }

  factory RatingWithUser.fromJson(Map<String, dynamic> json) => RatingWithUser(
        score: json['score'] as int,
        scoreSafety: json['safety_score'] as int?,
        scoreExperience: json['experience_score'] as int?,
        scoreAccessibility: json['accessibility_score'] as int?,
        scoreFamilyFriendly: json['family_friendly_score'] as int?,
        scoreCrowdedness: json['crowdedness_score'] as int?,
        note: json['note'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        user: RaterInfo.fromJson(json['user'] as Map<String, dynamic>),
        id: json['id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'score': score,
        if (scoreSafety != null) 'safety_score': scoreSafety,
        if (scoreExperience != null) 'experience_score': scoreExperience,
        if (scoreAccessibility != null) 'accessibility_score': scoreAccessibility,
        if (scoreFamilyFriendly != null) 'family_friendly_score': scoreFamilyFriendly,
        if (scoreCrowdedness != null) 'crowdedness_score': scoreCrowdedness,
        if (note != null) 'note': note,
        'updated_at': updatedAt.toIso8601String(),
        'user': user.toJson(),
        if (id != null) 'id': id,
      };
}

/// Star-count breakdown across all ratings.
class RatingDistribution {
  final int five;
  final int four;
  final int three;
  final int two;
  final int one;

  const RatingDistribution({
    required this.five,
    required this.four,
    required this.three,
    required this.two,
    required this.one,
  });

  int get total => five + four + three + two + one;

  /// Fraction (0.0–1.0) for a given star count.
  /// Returns 0.0 when total == 0 to prevent division by zero.
  double percentageFor(int stars) {
    if (total == 0) return 0.0;
    final count = switch (stars) {
      5 => five,
      4 => four,
      3 => three,
      2 => two,
      _ => one,
    };
    return count / total;
  }

  factory RatingDistribution.fromJson(Map<String, dynamic> json) =>
      RatingDistribution(
        five: json['five'] as int,
        four: json['four'] as int,
        three: json['three'] as int,
        two: json['two'] as int,
        one: json['one'] as int,
      );

  Map<String, dynamic> toJson() => {
        'five': five,
        'four': four,
        'three': three,
        'two': two,
        'one': one,
      };
}

/// Full ratings page payload from GET /itineraries/{id}/ratings.
class RatingsPage {
  /// null when there are no ratings yet.
  final double? ratingAvg;
  final int ratingCount;
  final RatingDistribution distribution;

  /// Individual ratings ordered by updated_at DESC (most recent first).
  final List<RatingWithUser> ratings;

  const RatingsPage({
    required this.ratingAvg,
    required this.ratingCount,
    required this.distribution,
    required this.ratings,
  });

  factory RatingsPage.fromJson(Map<String, dynamic> json) => RatingsPage(
        ratingAvg: (json['rating_avg'] as num?)?.toDouble(),
        ratingCount: json['rating_count'] as int,
        distribution: RatingDistribution.fromJson(
          json['distribution'] as Map<String, dynamic>,
        ),
        ratings: (json['ratings'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RatingWithUser.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'rating_avg': ratingAvg,
        'rating_count': ratingCount,
        'distribution': distribution.toJson(),
        'ratings': ratings.map((r) => r.toJson()).toList(),
      };
}
