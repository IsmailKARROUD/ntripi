// features/itineraries/domain/dimension_key.dart
//
// DimensionKey identifies one of the five rating dimensions.
// Used by DimensionRatingsScreen and client-side filtering helpers.

import 'package:flutter/material.dart';

enum DimensionKey {
  overall,
  safety,
  experience,
  accessibility,
  familyFriendly;

  static DimensionKey fromPath(String p) => switch (p) {
        'overall' => overall,
        'safety' => safety,
        'experience' => experience,
        'accessibility' => accessibility,
        'family_friendly' => familyFriendly,
        _ => overall,
      };

  String get pathSegment => switch (this) {
        overall => 'overall',
        safety => 'safety',
        experience => 'experience',
        accessibility => 'accessibility',
        familyFriendly => 'family_friendly',
      };

  String get label => switch (this) {
        overall => 'Overall',
        safety => 'Safety',
        experience => 'Experience',
        accessibility => 'Accessibility',
        familyFriendly => 'Family-friendly',
      };

  String get description => switch (this) {
        overall => 'General impression',
        safety => 'How safe you felt throughout',
        experience => 'Quality of the overall experience',
        accessibility => 'Ease of access for all abilities',
        familyFriendly => 'Suitability for children and families',
      };

  IconData get icon => switch (this) {
        overall => Icons.star_rounded,
        safety => Icons.shield_outlined,
        experience => Icons.emoji_emotions_outlined,
        accessibility => Icons.accessible_outlined,
        familyFriendly => Icons.family_restroom_outlined,
      };
}
