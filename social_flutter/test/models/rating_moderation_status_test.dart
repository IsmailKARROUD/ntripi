// test/models/rating_moderation_status_test.dart
//
// The banner on a review tile is driven entirely by RatingWithUser's parsed
// status, so the parse has to survive an older backend (field absent) and a
// newer one (value this build has never heard of).

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/shared/models/moderation_status.dart';

void main() {
  Map<String, dynamic> ratingJson({Object? status = _absent}) => {
        'score': 4,
        'safety_score': null,
        'experience_score': null,
        'accessibility_score': null,
        'family_friendly_score': null,
        'crowdedness_score': null,
        'note': 'a note',
        'updated_at': '2026-01-01T00:00:00Z',
        'user': {
          'user_id': 'u1',
          'username': 'someone',
          'display_name': 'Someone',
          'avatar_url': null,
        },
        'id': 'r1',
        if (status != _absent) 'moderation_status': status,
      };

  group('RatingWithUser.moderationStatus', () {
    test('Given the field is absent, Then it defaults to approved', () {
      final rating = RatingWithUser.fromJson(ratingJson());

      expect(rating.moderationStatus, ModerationStatus.approved);
      expect(rating.moderationStatus.isVisibleToAuthor, isFalse);
    });

    test('Given "hidden", Then it parses and is shown to the author', () {
      final rating = RatingWithUser.fromJson(ratingJson(status: 'hidden'));

      expect(rating.moderationStatus, ModerationStatus.hidden);
      expect(rating.moderationStatus.isVisibleToAuthor, isTrue);
    });

    test('Given "rejected", Then it is also shown to the author', () {
      final rating = RatingWithUser.fromJson(ratingJson(status: 'rejected'));

      expect(rating.moderationStatus.isVisibleToAuthor, isTrue);
    });

    test('Given an internal state, Then it is never shown to the author', () {
      for (final internal in ['pending', 'flagged']) {
        final rating = RatingWithUser.fromJson(ratingJson(status: internal));

        expect(rating.moderationStatus.isVisibleToAuthor, isFalse,
            reason: '$internal must stay internal');
      }
    });

    test('Given an unknown value from a newer backend, Then it degrades', () {
      final rating =
          RatingWithUser.fromJson(ratingJson(status: 'quarantined_v2'));

      expect(rating.moderationStatus, ModerationStatus.approved);
    });

    test('Given a round trip, Then the status survives toJson', () {
      final rating = RatingWithUser.fromJson(ratingJson(status: 'hidden'));

      final restored = RatingWithUser.fromJson(rating.toJson());

      expect(restored.moderationStatus, ModerationStatus.hidden);
    });
  });
}

const Object _absent = Object();
