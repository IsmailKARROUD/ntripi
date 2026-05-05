// features/itineraries/data/itinerary_repository.dart — Itinerary API calls.
//
// Follows the same repository pattern as AuthRepository and FollowRepository:
// each method maps directly to one API endpoint and returns a typed Dart object.
// Error handling is left to the caller via DioException.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/domain/allowed_user.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/my_rating.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';

class ItineraryRepository {
  final Dio _dio;

  const ItineraryRepository(this._dio);

  // ---------------------------------------------------------------------------
  // Itinerary CRUD
  // ---------------------------------------------------------------------------

  /// GET /itineraries/me — returns the authenticated user's itineraries.
  Future<List<Itinerary>> getMyItineraries() async {
    final response = await _dio.get<List<dynamic>>(kMyItinerariesEndpoint);
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  /// GET /users/{userId}/itineraries — returns itineraries visible to the
  /// authenticated user on another user's profile.
  Future<List<Itinerary>> getUserItineraries(String userId) async {
    final response = await _dio.get<List<dynamic>>(
      userItinerariesEndpoint(userId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  /// GET /itineraries/{id} — returns a single itinerary with full stop detail.
  Future<Itinerary> getItinerary(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>(itineraryEndpoint(id));
    return Itinerary.fromJson(response.data!);
  }

  /// POST /itineraries — create a new itinerary.
  Future<Itinerary> createItinerary(Map<String, dynamic> data) async {
    final response =
        await _dio.post<Map<String, dynamic>>(kItinerariesEndpoint, data: data);
    return Itinerary.fromJson(response.data!);
  }

  /// PATCH /itineraries/{id} — partial update.
  Future<Itinerary> updateItinerary(
    String id,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      itineraryEndpoint(id),
      data: data,
    );
    return Itinerary.fromJson(response.data!);
  }

  /// DELETE /itineraries/{id}
  Future<void> deleteItinerary(String id) async {
    await _dio.delete(itineraryEndpoint(id));
  }

  // ---------------------------------------------------------------------------
  // Stop CRUD
  // ---------------------------------------------------------------------------

  /// POST /itineraries/{itineraryId}/stops
  Future<Stop> addStop(String itineraryId, Map<String, dynamic> data) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryStopsEndpoint(itineraryId),
      data: data,
    );
    return Stop.fromJson(response.data!);
  }

  /// PATCH /itineraries/{itineraryId}/stops/{stopId}
  Future<Stop> updateStop(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      itineraryStopEndpoint(itineraryId, stopId),
      data: data,
    );
    return Stop.fromJson(response.data!);
  }

  /// DELETE /itineraries/{itineraryId}/stops/{stopId}
  Future<void> deleteStop(String itineraryId, String stopId) async {
    await _dio.delete(itineraryStopEndpoint(itineraryId, stopId));
  }

  /// PATCH /itineraries/{itineraryId}/stops/reorder
  /// Returns the full itinerary detail with updated positions.
  Future<Itinerary> reorderStops(
    String itineraryId,
    List<String> stopIds,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      itineraryStopsReorderEndpoint(itineraryId),
      data: {'stop_ids': stopIds},
    );
    return Itinerary.fromJson(response.data!);
  }

  // ---------------------------------------------------------------------------
  // Annotation CRUD
  // ---------------------------------------------------------------------------

  /// POST /itineraries/{itineraryId}/stops/{stopId}/annotations
  Future<Annotation> addAnnotation(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      stopAnnotationsEndpoint(itineraryId, stopId),
      data: data,
    );
    return Annotation.fromJson(response.data!);
  }

  /// DELETE /itineraries/{itineraryId}/stops/{stopId}/annotations/{annotationId}
  Future<void> deleteAnnotation(
    String itineraryId,
    String stopId,
    String annotationId,
  ) async {
    await _dio.delete(stopAnnotationEndpoint(itineraryId, stopId, annotationId));
  }

  /// PATCH /itineraries/{itineraryId}/stops/{stopId}/annotations/{annotationId}
  Future<Annotation> updateAnnotation(
    String itineraryId,
    String stopId,
    String annotationId, {
    String? content,
    AnnotationType? type,
  }) async {
    final body = <String, dynamic>{
      if (content != null) 'content': content,
      if (type != null) 'type': type.name,
    };
    final response = await _dio.patch<Map<String, dynamic>>(
      stopAnnotationEndpoint(itineraryId, stopId, annotationId),
      data: body,
    );
    return Annotation.fromJson(response.data!);
  }

  // ---------------------------------------------------------------------------
  // Itinerary-level annotation CRUD
  // ---------------------------------------------------------------------------

  /// POST /itineraries/{itineraryId}/annotations
  Future<ItineraryAnnotation> addItineraryAnnotation(
    String itineraryId,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryAnnotationsEndpoint(itineraryId),
      data: data,
    );
    return ItineraryAnnotation.fromJson(response.data!);
  }

  /// PATCH /itineraries/{itineraryId}/annotations/{annotationId}
  Future<ItineraryAnnotation> updateItineraryAnnotation(
    String itineraryId,
    String annotationId, {
    String? content,
    AnnotationType? type,
  }) async {
    final body = <String, dynamic>{
      if (content != null) 'content': content,
      if (type != null) 'type': type.name,
    };
    final response = await _dio.patch<Map<String, dynamic>>(
      itineraryAnnotationEndpoint(itineraryId, annotationId),
      data: body,
    );
    return ItineraryAnnotation.fromJson(response.data!);
  }

  /// DELETE /itineraries/{itineraryId}/annotations/{annotationId}
  Future<void> deleteItineraryAnnotation(
    String itineraryId,
    String annotationId,
  ) async {
    await _dio.delete(itineraryAnnotationEndpoint(itineraryId, annotationId));
  }

  // ---------------------------------------------------------------------------
  // Allowlist CRUD (restricted visibility)
  // ---------------------------------------------------------------------------

  /// GET /itineraries/{id}/allowed-users
  Future<List<AllowedUser>> getAllowedUsers(String itineraryId) async {
    final response = await _dio.get<List<dynamic>>(
      itineraryAllowedUsersEndpoint(itineraryId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(AllowedUser.fromJson)
        .toList();
  }

  /// POST /itineraries/{id}/allowed-users
  Future<AllowedUser> addAllowedUser(
    String itineraryId,
    String userId,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryAllowedUsersEndpoint(itineraryId),
      data: {'user_id': userId},
    );
    return AllowedUser.fromJson(response.data!);
  }

  /// DELETE /itineraries/{id}/allowed-users/{userId}
  Future<void> removeAllowedUser(String itineraryId, String userId) async {
    await _dio.delete(itineraryAllowedUserEndpoint(itineraryId, userId));
  }

  // ---------------------------------------------------------------------------
  // Transit segments
  // ---------------------------------------------------------------------------

  /// POST /itineraries/{id}/segments — create a segment with its legs.
  Future<TransitSegment> createSegment(
    String itineraryId,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itinerarySegmentsEndpoint(itineraryId),
      data: data,
    );
    return TransitSegment.fromJson(response.data!);
  }

  /// PATCH /itineraries/{id}/segments/{segmentId} — replace stops + legs.
  Future<TransitSegment> updateSegment(
    String itineraryId,
    String segmentId,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      itinerarySegmentEndpoint(itineraryId, segmentId),
      data: data,
    );
    return TransitSegment.fromJson(response.data!);
  }

  /// DELETE /itineraries/{id}/segments/{segmentId}
  Future<void> deleteSegment(String itineraryId, String segmentId) async {
    await _dio.delete(itinerarySegmentEndpoint(itineraryId, segmentId));
  }

  // ---------------------------------------------------------------------------
  // Cover image
  // ---------------------------------------------------------------------------

  /// POST /itineraries/{id}/image — upload or replace the cover image.
  /// Returns the new public URL for the cover image.
  Future<String> uploadCoverImage({
    required String itineraryId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryImageEndpoint(itineraryId),
      data: formData,
    );
    return response.data!['cover_image_url'] as String;
  }

  /// DELETE /itineraries/{id}/image — remove the cover image.
  Future<void> deleteCoverImage(String itineraryId) async {
    await _dio.delete(itineraryImageEndpoint(itineraryId));
  }

  // ---------------------------------------------------------------------------
  // Ratings
  // ---------------------------------------------------------------------------

  /// POST /itineraries/{id}/ratings — upsert the current user's rating.
  Future<MyRating> submitRating(String itineraryId, MyRating rating) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryRatingsEndpoint(itineraryId),
      data: rating.toJson(),
    );
    return MyRating.fromJson(response.data!);
  }

  /// DELETE /itineraries/{id}/ratings/me — remove the current user's rating.
  Future<void> deleteMyRating(String itineraryId) async {
    await _dio.delete(itineraryMyRatingEndpoint(itineraryId));
  }

  /// GET /itineraries/{id}/ratings — full ratings page with distribution + list.
  Future<RatingsPage> getRatingsPage(String itineraryId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      itineraryRatingsEndpoint(itineraryId),
    );
    return RatingsPage.fromJson(response.data!);
  }

  /// GET /itineraries/{id}/ratings/me — returns the user's rating or null if not rated.
  Future<MyRating?> getMyRating(String itineraryId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        itineraryMyRatingEndpoint(itineraryId),
      );
      return MyRating.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}

/// Provides the ItineraryRepository singleton, using the app-wide Dio client
/// (which carries the auth interceptor that attaches the Bearer token).
final itineraryRepositoryProvider = Provider<ItineraryRepository>((ref) {
  return ItineraryRepository(dio);
});
