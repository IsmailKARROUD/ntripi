// features/profile/data/profile_repository.dart — Profile API calls.

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/shared/models/user.dart';

class ProfileRepository {
  final Dio _dio;

  const ProfileRepository(this._dio);

  /// GET /users/me — own full profile (includes email).
  Future<User> getMyProfile() async {
    final response = await _dio.get(kMyProfileEndpoint);
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  /// GET /users/{userId} — public profile with follow status.
  Future<User> getUserProfile(String userId) async {
    final response = await _dio.get(userProfileEndpoint(userId));
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  /// PATCH /users/me — partial profile update.
  Future<User> updateMyProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
  }) async {
    // Build the request body with only the non-null fields.
    // This ensures we only update fields the user actually changed.
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (bio != null) data['bio'] = bio;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (isPrivate != null) data['is_private'] = isPrivate;

    final response = await _dio.patch(kMyProfileEndpoint, data: data);
    return User.fromJson(response.data as Map<String, dynamic>);
  }
}
