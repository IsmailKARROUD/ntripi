// features/itineraries/data/itinerary_repository.dart — Itinerary API calls.
//
// Follows the same repository pattern as AuthRepository and FollowRepository:
// each method maps directly to one API endpoint and returns a typed Dart object.
// Error handling is left to the caller via DioException.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';

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
}

/// Provides the ItineraryRepository singleton, using the app-wide Dio client
/// (which carries the auth interceptor that attaches the Bearer token).
final itineraryRepositoryProvider = Provider<ItineraryRepository>((ref) {
  return ItineraryRepository(dio);
});
