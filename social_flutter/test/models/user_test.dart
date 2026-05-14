// test/models/user_test.dart — Unit tests for the User model.
//
// These tests are pure Dart — no Flutter framework, no network, no platform
// channels. They run instantly and verify that JSON parsing, serialization,
// and copyWith behave correctly regardless of the rest of the app.
//
// Test naming follows: <method>_<scenario>_<expected result>

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/shared/models/user.dart';

// ---------------------------------------------------------------------------
// Shared test fixtures
// ---------------------------------------------------------------------------

/// A complete JSON object matching what the backend returns on GET /users/{id}.
/// Used as the base for all fromJson tests.
const _fullJson = {
  'id': 'user-uuid-123',
  'username': 'alice1',
  'email': 'alice@test.com',
  'display_name': 'Alice',
  'bio': 'Hello world',
  'avatar_url': 'https://example.com/alice.jpg',
  'is_private': false,
  'followers_count': 10,
  'following_count': 5,
  'is_following': true,
  'follow_is_pending': false,
  'created_at': '2024-01-15T10:30:00.000Z',
  'passport_countries': ['MA', 'FR'],
  'resident_country': 'BE',
  'languages': ['FR', 'AR', 'EN'],
};

/// A minimal JSON object with only required fields — optional fields are absent.
const _minimalJson = {
  'id': 'user-uuid-456',
  'username': 'bob1',
  'created_at': '2024-03-01T00:00:00.000Z',
};

void main() {
  group('User.fromJson', () {
    test('parses all fields correctly from a full JSON response', () {
      final user = User.fromJson(_fullJson);

      expect(user.id, 'user-uuid-123');
      expect(user.username, 'alice1');
      expect(user.email, 'alice@test.com');
      expect(user.displayName, 'Alice');
      expect(user.bio, 'Hello world');
      expect(user.avatarUrl, 'https://example.com/alice.jpg');
      expect(user.isPrivate, false);
      expect(user.followersCount, 10);
      expect(user.followingCount, 5);
      expect(user.isFollowing, true);
      expect(user.followIsPending, false);
      expect(user.createdAt, DateTime.parse('2024-01-15T10:30:00.000Z'));
    });

    test('nullable fields are null when absent from JSON', () {
      final user = User.fromJson(_minimalJson);

      // These fields are not in _minimalJson — they should all be null.
      expect(user.email, isNull);
      expect(user.displayName, isNull);
      expect(user.bio, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('is_private defaults to true when absent — fail-safe for privacy', () {
      // New default: accounts are private unless the server says otherwise.
      final user = User.fromJson(_minimalJson);
      expect(user.isPrivate, true);
    });

    test('follower/following counts default to 0 when absent', () {
      final user = User.fromJson(_minimalJson);
      expect(user.followersCount, 0);
      expect(user.followingCount, 0);
    });

    test('isFollowing and followIsPending default to false when absent', () {
      // These fields are only present on GET /users/{id} (public profile).
      // On GET /users/me they are absent, so they must default to false.
      final user = User.fromJson(_minimalJson);
      expect(user.isFollowing, false);
      expect(user.followIsPending, false);
    });

    test('created_at defaults to DateTime(2020) when absent', () {
      final json = Map<String, dynamic>.from(_minimalJson)
        ..remove('created_at');
      final user = User.fromJson(json);
      expect(user.createdAt, DateTime(2020));
    });

    test('parses passport_countries, resident_country, and languages from JSON',
        () {
      final user = User.fromJson(_fullJson);
      expect(user.passportCountries, ['MA', 'FR']);
      expect(user.residentCountry, 'BE');
      expect(user.languages, ['FR', 'AR', 'EN']);
    });

    test(
        'travel identity fields are null when absent — existing profiles unaffected',
        () {
      final user = User.fromJson(_minimalJson);
      expect(user.passportCountries, isNull);
      expect(user.residentCountry, isNull);
      expect(user.languages, isNull);
    });

    test('passport_countries can hold multiple codes (dual nationality)', () {
      final json = Map<String, dynamic>.from(_minimalJson)
        ..['passport_countries'] = ['MA', 'FR', 'ES'];
      final user = User.fromJson(json);
      expect(user.passportCountries, hasLength(3));
      expect(user.passportCountries, containsAll(['MA', 'FR', 'ES']));
    });

    test('languages can be an empty list', () {
      final json = Map<String, dynamic>.from(_minimalJson)
        ..['languages'] = <String>[];
      final user = User.fromJson(json);
      expect(user.languages, isEmpty);
    });
  });

  group('User.toJson', () {
    test('includes all non-null fields', () {
      final user = User.fromJson(_fullJson);
      final json = user.toJson();

      expect(json['id'], 'user-uuid-123');
      expect(json['username'], 'alice1');
      expect(json['email'], 'alice@test.com');
      expect(json['display_name'], 'Alice');
      expect(json['bio'], 'Hello world');
      expect(json['avatar_url'], 'https://example.com/alice.jpg');
      expect(json['is_private'], false);
      expect(json['followers_count'], 10);
      expect(json['following_count'], 5);
    });

    test('omits null optional fields (email, display_name, bio, avatar_url)', () {
      final user = User.fromJson(_minimalJson);
      final json = user.toJson();

      expect(json.containsKey('email'), false);
      expect(json.containsKey('display_name'), false);
      expect(json.containsKey('bio'), false);
      expect(json.containsKey('avatar_url'), false);
    });

    test('includes passport_countries, resident_country, and languages when set',
        () {
      final user = User.fromJson(_fullJson);
      final json = user.toJson();

      expect(json['passport_countries'], ['MA', 'FR']);
      expect(json['resident_country'], 'BE');
      expect(json['languages'], ['FR', 'AR', 'EN']);
    });

    test('omits travel identity keys when all are null', () {
      final user = User.fromJson(_minimalJson);
      final json = user.toJson();

      expect(json.containsKey('passport_countries'), false);
      expect(json.containsKey('resident_country'), false);
      expect(json.containsKey('languages'), false);
    });
  });

  group('User.copyWith', () {
    test('returns a new User with only the specified field changed', () {
      final original = User.fromJson(_fullJson);
      final updated = original.copyWith(username: 'alice2');

      // Changed field
      expect(updated.username, 'alice2');

      // Everything else stays the same
      expect(updated.id, original.id);
      expect(updated.email, original.email);
      expect(updated.isPrivate, original.isPrivate);
      expect(updated.followersCount, original.followersCount);
    });

    test('copyWith with no arguments preserves all original values', () {
      final original = User.fromJson(_fullJson);
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.username, original.username);
      expect(copy.email, original.email);
      expect(copy.isPrivate, original.isPrivate);
      expect(copy.followersCount, original.followersCount);
    });

    test('copyWith can update travel identity fields independently', () {
      final original = User.fromJson(_fullJson);

      final updated = original.copyWith(
        passportCountries: ['MA', 'FR', 'NL'],
        residentCountry: 'NL',
        languages: ['FR', 'NL'],
      );

      expect(updated.passportCountries, ['MA', 'FR', 'NL']);
      expect(updated.residentCountry, 'NL');
      expect(updated.languages, ['FR', 'NL']);
      // Other fields unaffected
      expect(updated.id, original.id);
      expect(updated.username, original.username);
    });

    test('copyWith with no arguments preserves travel identity fields', () {
      final original = User.fromJson(_fullJson);
      final copy = original.copyWith();

      expect(copy.passportCountries, original.passportCountries);
      expect(copy.residentCountry, original.residentCountry);
      expect(copy.languages, original.languages);
    });

    test('copyWith can update follow state for optimistic UI updates', () {
      // Simulates the optimistic update done in UserProfileNotifier
      // after the user taps the Follow button.
      final original = User.fromJson(_fullJson);
      final afterFollow = original.copyWith(
        isFollowing: true,
        followIsPending: false,
        followersCount: original.followersCount + 1,
      );

      expect(afterFollow.isFollowing, true);
      expect(afterFollow.followIsPending, false);
      expect(afterFollow.followersCount, original.followersCount + 1);
      // Other fields untouched
      expect(afterFollow.username, original.username);
    });
  });
}
