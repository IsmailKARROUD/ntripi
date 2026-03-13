// test/models/follow_test.dart — Unit tests for Follow, FollowRequestItem,
// and FollowerListItem models.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/shared/models/follow.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Follow
  // ---------------------------------------------------------------------------

  group('Follow.fromJson', () {
    const json = {
      'id': 'follow-uuid-1',
      'follower_id': 'user-uuid-a',
      'following_id': 'user-uuid-b',
      'status': 'accepted',
      'created_at': '2024-02-10T08:00:00.000Z',
    };

    test('parses all fields correctly', () {
      final follow = Follow.fromJson(json);

      expect(follow.id, 'follow-uuid-1');
      expect(follow.followerId, 'user-uuid-a');
      expect(follow.followingId, 'user-uuid-b');
      expect(follow.status, 'accepted');
      expect(follow.createdAt, DateTime.parse('2024-02-10T08:00:00.000Z'));
    });

    test('isPending returns true only when status is "pending"', () {
      final pending = Follow.fromJson({...json, 'status': 'pending'});
      final accepted = Follow.fromJson({...json, 'status': 'accepted'});

      expect(pending.isPending, true);
      expect(accepted.isPending, false);
    });

    test('isAccepted returns true only when status is "accepted"', () {
      final accepted = Follow.fromJson({...json, 'status': 'accepted'});
      final pending = Follow.fromJson({...json, 'status': 'pending'});

      expect(accepted.isAccepted, true);
      expect(pending.isAccepted, false);
    });
  });

  group('Follow.toJson', () {
    test('round-trips correctly — fromJson then toJson restores original values', () {
      const original = {
        'id': 'follow-uuid-1',
        'follower_id': 'user-uuid-a',
        'following_id': 'user-uuid-b',
        'status': 'pending',
        'created_at': '2024-02-10T08:00:00.000Z',
      };

      final json = Follow.fromJson(original).toJson();

      expect(json['id'], original['id']);
      expect(json['follower_id'], original['follower_id']);
      expect(json['following_id'], original['following_id']);
      expect(json['status'], original['status']);
    });
  });

  // ---------------------------------------------------------------------------
  // FollowRequestItem
  // ---------------------------------------------------------------------------

  group('FollowRequestItem.fromJson', () {
    test('parses all fields including nullable ones', () {
      final item = FollowRequestItem.fromJson({
        'follow_id': 'follow-uuid-2',
        'follower_id': 'user-uuid-c',
        'username': 'charlie1',
        'display_name': 'Charlie',
        'avatar_url': 'https://example.com/charlie.jpg',
        'requested_at': '2024-03-05T12:00:00.000Z',
      });

      expect(item.followId, 'follow-uuid-2');
      expect(item.followerId, 'user-uuid-c');
      expect(item.username, 'charlie1');
      expect(item.displayName, 'Charlie');
      expect(item.avatarUrl, 'https://example.com/charlie.jpg');
      expect(item.requestedAt, DateTime.parse('2024-03-05T12:00:00.000Z'));
    });

    test('display_name and avatar_url are null when absent', () {
      // Not all users have a display name or avatar set.
      final item = FollowRequestItem.fromJson({
        'follow_id': 'follow-uuid-3',
        'follower_id': 'user-uuid-d',
        'username': 'dave1',
        'requested_at': '2024-03-06T00:00:00.000Z',
      });

      expect(item.displayName, isNull);
      expect(item.avatarUrl, isNull);
    });
  });

  group('FollowRequestItem.toJson', () {
    test('omits null display_name and avatar_url', () {
      final item = FollowRequestItem.fromJson({
        'follow_id': 'follow-uuid-3',
        'follower_id': 'user-uuid-d',
        'username': 'dave1',
        'requested_at': '2024-03-06T00:00:00.000Z',
      });

      final json = item.toJson();

      expect(json.containsKey('display_name'), false);
      expect(json.containsKey('avatar_url'), false);
    });
  });

  // ---------------------------------------------------------------------------
  // FollowerListItem
  // ---------------------------------------------------------------------------

  group('FollowerListItem.fromJson', () {
    test('parses all fields correctly', () {
      final item = FollowerListItem.fromJson({
        'id': 'user-uuid-e',
        'username': 'eve1',
        'display_name': 'Eve',
        'avatar_url': 'https://example.com/eve.jpg',
        'is_private': true,
      });

      expect(item.id, 'user-uuid-e');
      expect(item.username, 'eve1');
      expect(item.displayName, 'Eve');
      expect(item.avatarUrl, 'https://example.com/eve.jpg');
      expect(item.isPrivate, true);
    });

    test('display_name and avatar_url are null when absent', () {
      final item = FollowerListItem.fromJson({
        'id': 'user-uuid-f',
        'username': 'frank1',
        'is_private': false,
      });

      expect(item.displayName, isNull);
      expect(item.avatarUrl, isNull);
    });

    test('is_private defaults to true when absent — fail-safe for privacy', () {
      // If the field is missing we assume private rather than public,
      // consistent with the backend default and User.fromJson.
      final item = FollowerListItem.fromJson({
        'id': 'user-uuid-g',
        'username': 'grace1',
      });

      expect(item.isPrivate, true);
    });
  });
}
