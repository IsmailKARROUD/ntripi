// features/itineraries/domain/my_rating.dart — The current user's rating for
// one itinerary, including optional sub-ratings from the extended dialog.

class MyRating {
  final int stars;
  final int? safetyStars;
  final int? experienceStars;
  final int? accessibilityStars;
  final int? familyFriendlyStars;

  const MyRating({
    required this.stars,
    this.safetyStars,
    this.experienceStars,
    this.accessibilityStars,
    this.familyFriendlyStars,
  });

  factory MyRating.fromJson(Map<String, dynamic> json) => MyRating(
        stars: json['stars'] as int,
        safetyStars: json['safety_stars'] as int?,
        experienceStars: json['experience_stars'] as int?,
        accessibilityStars: json['accessibility_stars'] as int?,
        familyFriendlyStars: json['family_friendly_stars'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'stars': stars,
        if (safetyStars != null) 'safety_stars': safetyStars,
        if (experienceStars != null) 'experience_stars': experienceStars,
        if (accessibilityStars != null) 'accessibility_stars': accessibilityStars,
        if (familyFriendlyStars != null) 'family_friendly_stars': familyFriendlyStars,
      };

  MyRating copyWith({
    int? stars,
    Object? safetyStars = _absent,
    Object? experienceStars = _absent,
    Object? accessibilityStars = _absent,
    Object? familyFriendlyStars = _absent,
  }) =>
      MyRating(
        stars: stars ?? this.stars,
        safetyStars: safetyStars == _absent ? this.safetyStars : safetyStars as int?,
        experienceStars: experienceStars == _absent ? this.experienceStars : experienceStars as int?,
        accessibilityStars: accessibilityStars == _absent ? this.accessibilityStars : accessibilityStars as int?,
        familyFriendlyStars: familyFriendlyStars == _absent ? this.familyFriendlyStars : familyFriendlyStars as int?,
      );
}

const _absent = Object();
