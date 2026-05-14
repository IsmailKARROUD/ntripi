// features/profile/data/profile_repository.dart — Profile API calls.

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/shared/models/user.dart';

/// Thrown when DELETE /users/me returns 401 (wrong password).
class PasswordIncorrectException implements Exception {
  const PasswordIncorrectException();
}

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

  /// DELETE /users/me — permanently delete the account.
  ///
  /// Throws [PasswordIncorrectException] on 401.
  /// Clears the stored token on success.
  Future<void> deleteAccount(String password) async {
    try {
      await _dio.delete(kMyProfileEndpoint, data: {'password': password});
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const PasswordIncorrectException();
      }
      rethrow;
    }
    await deleteToken();
  }

  /// PATCH /users/me — partial profile update.
  Future<User> updateMyProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    bool? isPrivate,
    List<String>? passportCountries,
    bool passportCountriesChanged = false,
    String? residentCountry,
    bool clearResidentCountry = false,
    List<String>? languages,
    bool languagesChanged = false,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (bio != null) data['bio'] = bio;
    if (clearAvatarUrl) {
      data['avatar_url'] = null;
    } else if (avatarUrl != null) {
      data['avatar_url'] = avatarUrl;
    }
    if (isPrivate != null) data['is_private'] = isPrivate;
    if (passportCountriesChanged) data['passport_countries'] = passportCountries ?? [];
    if (clearResidentCountry) {
      data['resident_country'] = null;
    } else if (residentCountry != null) {
      data['resident_country'] = residentCountry;
    }
    if (languagesChanged) data['languages'] = languages ?? [];

    final response = await _dio.patch(kMyProfileEndpoint, data: data);
    return User.fromJson(response.data as Map<String, dynamic>);
  }
}
