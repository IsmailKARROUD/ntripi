// features/itineraries/domain/my_rating.dart — The current user's rating for
// one itinerary, including optional sub-ratings from the extended dialog.

class MyRating {
  final int stars;
  final int? safetyStars;
  final int? experienceStars;
  final int? accessibilityStars;
  final int? familyFriendlyStars;

  /// Crowdedness — higher = better (5 = pleasantly uncrowded, 1 = overcrowded).
  final int? crowdednessStars;

  /// Optional Markdown-source review note. Rendered link-inert client-side.
  final String? note;

  const MyRating({
    required this.stars,
    this.safetyStars,
    this.experienceStars,
    this.accessibilityStars,
    this.familyFriendlyStars,
    this.crowdednessStars,
    this.note,
  });

  factory MyRating.fromJson(Map<String, dynamic> json) => MyRating(
        stars: json['stars'] as int,
        safetyStars: json['safety_stars'] as int?,
        experienceStars: json['experience_stars'] as int?,
        accessibilityStars: json['accessibility_stars'] as int?,
        familyFriendlyStars: json['family_friendly_stars'] as int?,
        crowdednessStars: json['crowdedness_stars'] as int?,
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'stars': stars,
        if (safetyStars != null) 'safety_stars': safetyStars,
        if (experienceStars != null) 'experience_stars': experienceStars,
        if (accessibilityStars != null) 'accessibility_stars': accessibilityStars,
        if (familyFriendlyStars != null) 'family_friendly_stars': familyFriendlyStars,
        if (crowdednessStars != null) 'crowdedness_stars': crowdednessStars,
        if (note != null) 'note': note,
      };

  MyRating copyWith({
    int? stars,
    Object? safetyStars = _absent,
    Object? experienceStars = _absent,
    Object? accessibilityStars = _absent,
    Object? familyFriendlyStars = _absent,
    Object? crowdednessStars = _absent,
    Object? note = _absent,
  }) =>
      MyRating(
        stars: stars ?? this.stars,
        safetyStars: safetyStars == _absent ? this.safetyStars : safetyStars as int?,
        experienceStars: experienceStars == _absent ? this.experienceStars : experienceStars as int?,
        accessibilityStars: accessibilityStars == _absent ? this.accessibilityStars : accessibilityStars as int?,
        familyFriendlyStars: familyFriendlyStars == _absent ? this.familyFriendlyStars : familyFriendlyStars as int?,
        crowdednessStars: crowdednessStars == _absent ? this.crowdednessStars : crowdednessStars as int?,
        note: note == _absent ? this.note : note as String?,
      );
}

const _absent = Object();
