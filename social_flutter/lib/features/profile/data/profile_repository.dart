// features/profile/data/profile_repository.dart — Profile API calls.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/features/profile/domain/violation.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
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
  /// Re-auth credential depends on account type: password accounts pass
  /// [password]; passwordless (SSO) accounts pass their provider token
  /// ([googleIdToken] today). Throws [PasswordIncorrectException] only on the
  /// password path's 401 — a 401 on the Google path is a token error surfaced
  /// generically by the caller. Clears the stored token on success.
  Future<void> deleteAccount({String? password, String? googleIdToken}) async {
    final data = <String, dynamic>{};
    if (password != null) data['password'] = password;
    if (googleIdToken != null) data['google_id_token'] = googleIdToken;
    try {
      await _dio.delete(kMyProfileEndpoint, data: data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && password != null) {
        throw const PasswordIncorrectException();
      }
      rethrow;
    }
    await deleteToken();
  }

  /// PATCH /users/me — partial profile update.
  ///
  /// Avatar/cover images are NOT settable here — they're managed by the
  /// dedicated upload (POST) / delete endpoints, which run the moderation
  /// pipeline. The server rejects external avatar_url/cover_image_url values.
  Future<User> updateMyProfile({
    String? displayName,
    String? bio,
    bool? isPrivate,
    List<String>? passportCountries,
    bool passportCountriesChanged = false,
    String? residentCountry,
    bool clearResidentCountry = false,
    List<String>? languages,
    bool languagesChanged = false,
    bool? notifyRatings,
    bool? notifySaves,
    bool? notifyFollowAccepted,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (bio != null) data['bio'] = bio;
    if (isPrivate != null) data['is_private'] = isPrivate;
    if (passportCountriesChanged) data['passport_countries'] = passportCountries ?? [];
    if (clearResidentCountry) {
      data['resident_country'] = null;
    } else if (residentCountry != null) {
      data['resident_country'] = residentCountry;
    }
    if (languagesChanged) data['languages'] = languages ?? [];
    // Notification switches ride the same partial update — only the one the
    // user actually moved is sent.
    if (notifyRatings != null) data['notify_ratings'] = notifyRatings;
    if (notifySaves != null) data['notify_saves'] = notifySaves;
    if (notifyFollowAccepted != null) {
      data['notify_follow_accepted'] = notifyFollowAccepted;
    }

    final response = await _dio.patch(kMyProfileEndpoint, data: data);
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  // -------------------------------------------------------------------------
  // Image uploads — multipart binary endpoints. Server processes via the
  // 1200×630 pipeline (cover_image) for both avatar and cover. Avatar gets
  // center-cropped into a circle on the client by ClipOval+BoxFit.cover.
  // -------------------------------------------------------------------------

  /// POST /users/me/avatar — multipart upload. Returns the new avatar URL.
  Future<String> uploadAvatarImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      kMyAvatarEndpoint,
      data: form,
    );
    return response.data!['avatar_url'] as String;
  }

  /// DELETE /users/me/avatar — clear the avatar.
  Future<void> deleteAvatarImage() async {
    await _dio.delete(kMyAvatarEndpoint);
  }

  /// POST /users/me/cover-image — multipart upload. Returns the new cover URL.
  Future<String> uploadCoverImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      kMyCoverImageEndpoint,
      data: form,
    );
    return response.data!['cover_image_url'] as String;
  }

  /// DELETE /users/me/cover-image — clear the cover.
  Future<void> deleteCoverImage() async {
    await _dio.delete(kMyCoverImageEndpoint);
  }

  // -------------------------------------------------------------------------
  // Moderation status / appeals
  // -------------------------------------------------------------------------

  /// GET /appeals/violations — moderation actions against the current user.
  Future<List<Violation>> getViolations() async {
    final response = await _dio.get<Map<String, dynamic>>(kViolationsEndpoint);
    final list = (response.data!['violations'] as List).cast<Map<String, dynamic>>();
    return list.map(Violation.fromJson).toList();
  }

  /// POST /appeals — contest a moderation action.
  ///
  /// The server enforces one open appeal per item (409 `appeal_already_pending`)
  /// and a 30-day lock after a rejection (429 `appeal_cooldown`); callers surface
  /// those codes via [apiErrorCode].
  Future<void> submitAppeal({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await _dio.post(kAppealsEndpoint, data: {
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
    });
  }

  /// GET /users/{userId}/locations — aggregate stop coords visible to viewer.
  Future<List<VisitedLocation>> getUserLocations(String userId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      userLocationsEndpoint(userId),
    );
    final list = (response.data!['locations'] as List).cast<Map<String, dynamic>>();
    return list.map(VisitedLocation.fromJson).toList();
  }
}
