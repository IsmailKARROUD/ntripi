// features/itineraries/domain/dimension_key.dart
//
// DimensionKey identifies one of the five rating dimensions.
// Used by DimensionRatingsScreen and client-side filtering helpers.

import 'package:flutter/material.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

enum DimensionKey {
  overall,
  safety,
  experience,
  accessibility,
  familyFriendly,
  crowdedness;

  static DimensionKey fromPath(String p) => switch (p) {
        'overall' => overall,
        'safety' => safety,
        'experience' => experience,
        'accessibility' => accessibility,
        'family_friendly' => familyFriendly,
        'crowdedness' => crowdedness,
        _ => overall,
      };

  String get pathSegment => switch (this) {
        overall => 'overall',
        safety => 'safety',
        experience => 'experience',
        accessibility => 'accessibility',
        familyFriendly => 'family_friendly',
        crowdedness => 'crowdedness',
      };

  // Reuses the rate-dialog's *Label keys so the same dimension never shows
  // two different names.
  String label(AppLocalizations l10n) => switch (this) {
        overall => l10n.dimensionOverall,
        safety => l10n.safetyLabel,
        experience => l10n.experienceLabel,
        accessibility => l10n.accessibilityLabel,
        familyFriendly => l10n.familyFriendlyLabel,
        crowdedness => l10n.crowdednessLabel,
      };

  String description(AppLocalizations l10n) => switch (this) {
        overall => l10n.dimensionOverallDesc,
        safety => l10n.dimensionSafetyDesc,
        experience => l10n.dimensionExperienceDesc,
        accessibility => l10n.dimensionAccessibilityDesc,
        familyFriendly => l10n.dimensionFamilyFriendlyDesc,
        // Higher = better: 5 = pleasantly uncrowded, 1 = overcrowded.
        crowdedness => l10n.dimensionCrowdednessDesc,
      };

  IconData get icon => switch (this) {
        overall => Icons.star_rounded,
        safety => Icons.shield_outlined,
        experience => Icons.emoji_emotions_outlined,
        accessibility => Icons.accessible_outlined,
        familyFriendly => Icons.family_restroom_outlined,
        crowdedness => Icons.groups_outlined,
      };

  /// Uncrowded (crowdedness) is rendered inverted: filled people = crowd present
  /// (bad/red), so the fill grows from the right and empties are colored too.
  bool get invertedRating => this == crowdedness;

  /// Glyphs used to render this dimension's score as an N-of-5 fill row.
  /// Crowdedness uses person icons instead of stars; people have no half
  /// variant, so the half tier falls back to a filled person.
  ({IconData filled, IconData half, IconData empty}) get ratingGlyphs =>
      switch (this) {
        crowdedness => (
            filled: Icons.person,
            half: Icons.person,
            empty: Icons.person_outline,
          ),
        _ => (
            filled: Icons.star_rounded,
            half: Icons.star_half_rounded,
            empty: Icons.star_outline_rounded,
          ),
      };
}
