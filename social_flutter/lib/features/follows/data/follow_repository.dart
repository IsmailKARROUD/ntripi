// features/follows/data/follow_repository.dart — Follow/unfollow API calls.

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/shared/models/follow.dart';

/// Rows per page for the followers / following lists. The server's default is
/// 20 and its ceiling 100; asking explicitly keeps the client in charge.
const kFollowListPageSize = 50;

class FollowRepository {
  final Dio _dio;

  const FollowRepository(this._dio);

  /// POST /users/{userId}/follow
  /// Returns the created Follow record (with status = 'pending' or 'accepted').
  Future<Follow> followUser(String userId) async {
    final response = await _dio.post(followEndpoint(userId));
    return Follow.fromJson(response.data as Map<String, dynamic>);
  }

  /// DELETE /users/{userId}/follow
  /// Unfollows or cancels a pending request.
  Future<void> unfollowUser(String userId) async {
    await _dio.delete(followEndpoint(userId));
  }

  /// GET /users/me/follow-requests
  /// Returns the list of pending incoming follow requests.
  Future<List<FollowRequestItem>> getFollowRequests({
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get(
      kFollowRequestsEndpoint,
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((item) => FollowRequestItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// POST /users/me/follow-requests/{followId}/accept
  Future<Follow> acceptFollowRequest(String followId) async {
    final response = await _dio.post(acceptFollowRequestEndpoint(followId));
    return Follow.fromJson(response.data as Map<String, dynamic>);
  }

  /// DELETE /users/me/follow-requests/{followId}
  /// Rejects (deletes) a pending follow request.
  Future<void> rejectFollowRequest(String followId) async {
    await _dio.delete(rejectFollowRequestEndpoint(followId));
  }

  /// GET /users/{userId}/followers — accepted followers of a user, newest
  /// first, one page at a time.
  Future<List<FollowerListItem>> getFollowers(
    String userId, {
    int limit = kFollowListPageSize,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get(
      followersEndpoint(userId),
      queryParameters: {'limit': limit, 'offset': offset},
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((item) => FollowerListItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// GET /users/{userId}/following — users that this user follows, newest
  /// first, one page at a time.
  Future<List<FollowerListItem>> getFollowing(
    String userId, {
    int limit = kFollowListPageSize,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get(
      followingEndpoint(userId),
      queryParameters: {'limit': limit, 'offset': offset},
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((item) => FollowerListItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
