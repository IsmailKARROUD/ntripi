// features/itineraries/data/itinerary_repository.dart — Itinerary API calls.
//
// ETAG / IF-MATCH FLOW:
//   Every mutation method (addStop, deleteStop, addAnnotation, …) requires an
//   [etag] parameter — the quoted updated_at timestamp from the last server
//   response, e.g. '"2026-05-07T14:23:11Z"'.
//
//   The repository adds this as the HTTP If-Match header. The server compares
//   it to the itinerary's current updated_at:
//     - Match  → mutation proceeds; new ETag returned in response header.
//     - Stale  → 412 Precondition Failed → repository throws ItineraryStaleException.
//     - Missing→ 428 Precondition Required (shouldn't happen from this repo).
//
// WHO PROVIDES THE ETAG?
//   ItineraryDetailNotifier._etag reads it from the currently loaded state
//   (state.value?.eTag). Every mutation in the notifier passes that value down
//   to the repository without the presentation layer needing to think about it.

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

/// Thrown when the server returns 412 Precondition Failed.
///
/// This means the itinerary was modified from another device (or another tab)
/// after the client's last fetch. The presentation layer should catch this,
/// show a "reload" dialog, and re-fetch the itinerary before retrying.
class ItineraryStaleException implements Exception {
  const ItineraryStaleException();
  @override
  String toString() =>
      'ItineraryStaleException: itinerary modified remotely, please reload';
}

/// Convenience helper to build Dio options with the If-Match header.
/// The [etag] value must already be quoted: '"2026-05-07T14:23:11Z"'.
Options _ifMatch(String etag) => Options(headers: {'If-Match': etag});

class ItineraryRepository {
  final Dio _dio;

  const ItineraryRepository(this._dio);

  // ---------------------------------------------------------------------------
  // Itinerary CRUD
  // ---------------------------------------------------------------------------

  Future<List<Itinerary>> getMyItineraries() async {
    final response = await _dio.get<List<dynamic>>(kMyItinerariesEndpoint);
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  Future<List<Itinerary>> getUserItineraries(String userId) async {
    final response = await _dio.get<List<dynamic>>(
      userItinerariesEndpoint(userId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  Future<Itinerary> getItinerary(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>(itineraryEndpoint(id));
    return Itinerary.fromJson(response.data!);
  }

  Future<Itinerary> createItinerary(Map<String, dynamic> data) async {
    final response =
        await _dio.post<Map<String, dynamic>>(kItinerariesEndpoint, data: data);
    return Itinerary.fromJson(response.data!);
  }

  Future<Itinerary> updateItinerary(String id, Map<String, dynamic> data) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      itineraryEndpoint(id),
      data: data,
    );
    return Itinerary.fromJson(response.data!);
  }

  Future<void> deleteItinerary(String id) async {
    await _dio.delete(itineraryEndpoint(id));
  }

  // ---------------------------------------------------------------------------
  // Stop CRUD — all require ETag
  // ---------------------------------------------------------------------------

  Future<Stop> addStop(
    String itineraryId,
    Map<String, dynamic> data, {
    required String etag,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        itineraryStopsEndpoint(itineraryId),
        data: data,
        options: _ifMatch(etag),
      );
      return Stop.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  Future<Stop> updateStop(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data, {
    required String etag,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        itineraryStopEndpoint(itineraryId, stopId),
        data: data,
        options: _ifMatch(etag),
      );
      return Stop.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  Future<void> deleteStop(
    String itineraryId,
    String stopId, {
    required String etag,
  }) async {
    try {
      await _dio.delete(
        itineraryStopEndpoint(itineraryId, stopId),
        options: _ifMatch(etag),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Annotation CRUD — all require ETag
  // ---------------------------------------------------------------------------

  Future<Annotation> addAnnotation(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data, {
    required String etag,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        stopAnnotationsEndpoint(itineraryId, stopId),
        data: data,
        options: _ifMatch(etag),
      );
      return Annotation.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  Future<void> deleteAnnotation(
    String itineraryId,
    String stopId,
    String annotationId, {
    required String etag,
  }) async {
    try {
      await _dio.delete(
        stopAnnotationEndpoint(itineraryId, stopId, annotationId),
        options: _ifMatch(etag),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  Future<Annotation> updateAnnotation(
    String itineraryId,
    String stopId,
    String annotationId, {
    String? content,
    AnnotationType? type,
    required String etag,
  }) async {
    final body = <String, dynamic>{
      if (content != null) 'content': content,
      if (type != null) 'type': type.name,
    };
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        stopAnnotationEndpoint(itineraryId, stopId, annotationId),
        data: body,
        options: _ifMatch(etag),
      );
      return Annotation.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Itinerary-level annotation CRUD — all require ETag
  // ---------------------------------------------------------------------------

  Future<ItineraryAnnotation> addItineraryAnnotation(
    String itineraryId,
    Map<String, dynamic> data, {
    required String etag,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        itineraryAnnotationsEndpoint(itineraryId),
        data: data,
        options: _ifMatch(etag),
      );
      return ItineraryAnnotation.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  Future<ItineraryAnnotation> updateItineraryAnnotation(
    String itineraryId,
    String annotationId, {
    String? content,
    AnnotationType? type,
    required String etag,
  }) async {
    final body = <String, dynamic>{
      if (content != null) 'content': content,
      if (type != null) 'type': type.name,
    };
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        itineraryAnnotationEndpoint(itineraryId, annotationId),
        data: body,
        options: _ifMatch(etag),
      );
      return ItineraryAnnotation.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  Future<void> deleteItineraryAnnotation(
    String itineraryId,
    String annotationId, {
    required String etag,
  }) async {
    try {
      await _dio.delete(
        itineraryAnnotationEndpoint(itineraryId, annotationId),
        options: _ifMatch(etag),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) throw const ItineraryStaleException();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Allowlist CRUD
  // ---------------------------------------------------------------------------

  Future<List<AllowedUser>> getAllowedUsers(String itineraryId) async {
    final response = await _dio.get<List<dynamic>>(
      itineraryAllowedUsersEndpoint(itineraryId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(AllowedUser.fromJson)
        .toList();
  }

  Future<AllowedUser> addAllowedUser(String itineraryId, String userId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryAllowedUsersEndpoint(itineraryId),
      data: {'user_id': userId},
    );
    return AllowedUser.fromJson(response.data!);
  }

  Future<void> removeAllowedUser(String itineraryId, String userId) async {
    await _dio.delete(itineraryAllowedUserEndpoint(itineraryId, userId));
  }

  // ---------------------------------------------------------------------------
  // Transit segments
  // ---------------------------------------------------------------------------

  Future<TransitSegment> createSegment(
      String itineraryId, Map<String, dynamic> data) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itinerarySegmentsEndpoint(itineraryId),
      data: data,
    );
    return TransitSegment.fromJson(response.data!);
  }

  Future<TransitSegment> updateSegment(
      String itineraryId, String segmentId, Map<String, dynamic> data) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      itinerarySegmentEndpoint(itineraryId, segmentId),
      data: data,
    );
    return TransitSegment.fromJson(response.data!);
  }

  Future<void> deleteSegment(String itineraryId, String segmentId) async {
    await _dio.delete(itinerarySegmentEndpoint(itineraryId, segmentId));
  }

  // ---------------------------------------------------------------------------
  // Cover image
  // ---------------------------------------------------------------------------

  Future<String> uploadCoverImage({
    required String itineraryId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryImageEndpoint(itineraryId),
      data: formData,
    );
    return response.data!['cover_image_url'] as String;
  }

  Future<void> deleteCoverImage(String itineraryId) async {
    await _dio.delete(itineraryImageEndpoint(itineraryId));
  }

  // ---------------------------------------------------------------------------
  // Ratings
  // ---------------------------------------------------------------------------

  Future<MyRating> submitRating(String itineraryId, MyRating rating) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryRatingsEndpoint(itineraryId),
      data: rating.toJson(),
    );
    return MyRating.fromJson(response.data!);
  }

  Future<void> deleteMyRating(String itineraryId) async {
    await _dio.delete(itineraryMyRatingEndpoint(itineraryId));
  }

  Future<RatingsPage> getRatingsPage(String itineraryId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      itineraryRatingsEndpoint(itineraryId),
    );
    return RatingsPage.fromJson(response.data!);
  }

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

final itineraryRepositoryProvider = Provider<ItineraryRepository>((ref) {
  return ItineraryRepository(dio);
});
