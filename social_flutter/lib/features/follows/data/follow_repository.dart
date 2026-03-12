// features/follows/data/follow_repository.dart — Follow/unfollow API calls.

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/shared/models/follow.dart';

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
  Future<List<FollowRequestItem>> getFollowRequests() async {
    final response = await _dio.get(kFollowRequestsEndpoint);
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
}
