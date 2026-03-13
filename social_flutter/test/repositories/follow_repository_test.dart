// test/repositories/follow_repository_test.dart — Unit tests for FollowRepository.
//
// Covers every public method:
//   followUser, unfollowUser, getFollowRequests,
//   acceptFollowRequest, rejectFollowRequest,
//   getFollowers, getFollowing.
//
// All Dio HTTP calls are intercepted by DioAdapter — no real network needed.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Shared fixtures
  // ---------------------------------------------------------------------------

  /// A Follow JSON object as returned by POST /users/{id}/follow
  /// or POST /users/me/follow-requests/{id}/accept.
  Map<String, dynamic> _followJson({String status = 'accepted'}) => {
        'id': 'follow-uuid-1',
        'follower_id': 'user-uuid-a',
        'following_id': 'user-uuid-b',
        'status': status,
        'created_at': '2024-04-01T10:00:00.000Z',
      };

  /// A single FollowRequestItem as returned inside the follow-requests list.
  const _followRequestJson = {
    'follow_id': 'follow-uuid-2',
    'follower_id': 'user-uuid-c',
    'username': 'charlie1',
    'display_name': 'Charlie',
    'avatar_url': 'https://example.com/charlie.jpg',
    'requested_at': '2024-04-02T08:00:00.000Z',
  };

  /// A FollowerListItem as returned by the followers/following list endpoints.
  const _followerListItemJson = {
    'id': 'user-uuid-d',
    'username': 'dave1',
    'display_name': 'Dave',
    'avatar_url': 'https://example.com/dave.jpg',
    'is_private': false,
  };

  /// Creates a fresh Dio + DioAdapter pair to prevent test cross-contamination.
  (Dio, DioAdapter) _makeDio() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final adapter = DioAdapter(dio: dio);
    return (dio, adapter);
  }

  // ---------------------------------------------------------------------------
  // followUser()
  // ---------------------------------------------------------------------------

  group('FollowRepository.followUser', () {
    test('sends POST to correct endpoint and returns Follow with accepted status',
        () async {
      final (dio, adapter) = _makeDio();
      const targetUserId = 'user-uuid-b';

      adapter.onPost(
        followEndpoint(targetUserId),
        (server) => server.reply(201, _followJson(status: 'accepted')),
      );

      final repo = FollowRepository(dio);
      final follow = await repo.followUser(targetUserId);

      expect(follow.id, 'follow-uuid-1');
      expect(follow.followingId, targetUserId);
      expect(follow.isAccepted, true);
      expect(follow.isPending, false);
    });

    test('returns Follow with pending status for private accounts', () async {
      final (dio, adapter) = _makeDio();
      const targetUserId = 'user-uuid-private';

      // Private accounts → follow request goes to pending.
      adapter.onPost(
        followEndpoint(targetUserId),
        (server) => server.reply(
          201,
          {
            'id': 'follow-uuid-pending',
            'follower_id': 'user-uuid-a',
            'following_id': targetUserId,
            'status': 'pending',
            'created_at': '2024-04-01T10:00:00.000Z',
          },
        ),
      );

      final repo = FollowRepository(dio);
      final follow = await repo.followUser(targetUserId);

      expect(follow.isPending, true);
      expect(follow.isAccepted, false);
    });

    test('throws DioException on 404 when target user does not exist', () async {
      final (dio, adapter) = _makeDio();
      const targetUserId = 'nonexistent-user';

      adapter.onPost(
        followEndpoint(targetUserId),
        (server) => server.reply(404, {'detail': 'User not found'}),
      );

      final repo = FollowRepository(dio);
      expect(
        () => repo.followUser(targetUserId),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // unfollowUser()
  // ---------------------------------------------------------------------------

  group('FollowRepository.unfollowUser', () {
    test('sends DELETE to correct endpoint and completes without error',
        () async {
      final (dio, adapter) = _makeDio();
      const targetUserId = 'user-uuid-b';

      // 204 No Content — standard response for a successful DELETE.
      adapter.onDelete(
        followEndpoint(targetUserId),
        (server) => server.reply(204, null),
      );

      final repo = FollowRepository(dio);
      await expectLater(repo.unfollowUser(targetUserId), completes);
    });

    test('throws DioException on 404 when follow relationship does not exist',
        () async {
      final (dio, adapter) = _makeDio();
      const targetUserId = 'user-uuid-not-following';

      adapter.onDelete(
        followEndpoint(targetUserId),
        (server) => server.reply(404, {'detail': 'Follow not found'}),
      );

      final repo = FollowRepository(dio);
      expect(
        () => repo.unfollowUser(targetUserId),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // getFollowRequests()
  // ---------------------------------------------------------------------------

  group('FollowRepository.getFollowRequests', () {
    test('returns a list of FollowRequestItems on 200', () async {
      final (dio, adapter) = _makeDio();

      adapter.onGet(
        kFollowRequestsEndpoint,
        (server) => server.reply(200, [_followRequestJson]),
      );

      final repo = FollowRepository(dio);
      final requests = await repo.getFollowRequests();

      expect(requests, hasLength(1));
      expect(requests.first.followId, 'follow-uuid-2');
      expect(requests.first.username, 'charlie1');
      expect(requests.first.displayName, 'Charlie');
      expect(requests.first.avatarUrl, 'https://example.com/charlie.jpg');
    });

    test('returns an empty list when there are no pending requests', () async {
      final (dio, adapter) = _makeDio();

      adapter.onGet(
        kFollowRequestsEndpoint,
        (server) => server.reply(200, []),
      );

      final repo = FollowRepository(dio);
      final requests = await repo.getFollowRequests();

      expect(requests, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // acceptFollowRequest()
  // ---------------------------------------------------------------------------

  group('FollowRepository.acceptFollowRequest', () {
    test('sends POST to correct endpoint and returns accepted Follow', () async {
      final (dio, adapter) = _makeDio();
      const followId = 'follow-uuid-2';

      adapter.onPost(
        acceptFollowRequestEndpoint(followId),
        (server) => server.reply(200, _followJson(status: 'accepted')),
      );

      final repo = FollowRepository(dio);
      final follow = await repo.acceptFollowRequest(followId);

      expect(follow.isAccepted, true);
    });
  });

  // ---------------------------------------------------------------------------
  // rejectFollowRequest()
  // ---------------------------------------------------------------------------

  group('FollowRepository.rejectFollowRequest', () {
    test('sends DELETE to correct endpoint and completes without error',
        () async {
      final (dio, adapter) = _makeDio();
      const followId = 'follow-uuid-2';

      adapter.onDelete(
        rejectFollowRequestEndpoint(followId),
        (server) => server.reply(204, null),
      );

      final repo = FollowRepository(dio);
      await expectLater(repo.rejectFollowRequest(followId), completes);
    });
  });

  // ---------------------------------------------------------------------------
  // getFollowers()
  // ---------------------------------------------------------------------------

  group('FollowRepository.getFollowers', () {
    test('returns a list of FollowerListItems on 200', () async {
      final (dio, adapter) = _makeDio();
      const userId = 'user-uuid-b';

      adapter.onGet(
        followersEndpoint(userId),
        (server) => server.reply(200, [_followerListItemJson]),
      );

      final repo = FollowRepository(dio);
      final followers = await repo.getFollowers(userId);

      expect(followers, hasLength(1));
      expect(followers.first.id, 'user-uuid-d');
      expect(followers.first.username, 'dave1');
      expect(followers.first.displayName, 'Dave');
      expect(followers.first.isPrivate, false);
    });

    test('returns an empty list when the user has no followers', () async {
      final (dio, adapter) = _makeDio();
      const userId = 'user-uuid-new';

      adapter.onGet(
        followersEndpoint(userId),
        (server) => server.reply(200, []),
      );

      final repo = FollowRepository(dio);
      final followers = await repo.getFollowers(userId);

      expect(followers, isEmpty);
    });

    test('throws DioException on 403 when the account is private', () async {
      final (dio, adapter) = _makeDio();
      const userId = 'user-uuid-private';

      adapter.onGet(
        followersEndpoint(userId),
        (server) => server.reply(403, {'detail': 'This list is private'}),
      );

      final repo = FollowRepository(dio);
      expect(
        () => repo.getFollowers(userId),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // getFollowing()
  // ---------------------------------------------------------------------------

  group('FollowRepository.getFollowing', () {
    test('returns a list of FollowerListItems on 200', () async {
      final (dio, adapter) = _makeDio();
      const userId = 'user-uuid-b';

      adapter.onGet(
        followingEndpoint(userId),
        (server) => server.reply(200, [_followerListItemJson]),
      );

      final repo = FollowRepository(dio);
      final following = await repo.getFollowing(userId);

      expect(following, hasLength(1));
      expect(following.first.username, 'dave1');
    });

    test('throws DioException on 403 for private following list', () async {
      final (dio, adapter) = _makeDio();
      const userId = 'user-uuid-private';

      adapter.onGet(
        followingEndpoint(userId),
        (server) => server.reply(403, {'detail': 'This list is private'}),
      );

      final repo = FollowRepository(dio);
      expect(
        () => repo.getFollowing(userId),
        throwsA(isA<DioException>()),
      );
    });
  });
}
