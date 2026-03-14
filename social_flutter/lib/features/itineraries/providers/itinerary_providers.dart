// features/itineraries/providers/itinerary_providers.dart — Riverpod state management.
//
// Three providers:
//   myItinerariesProvider — list of the current user's itineraries (create/delete)
//   itineraryDetailProvider — full detail for one itinerary (stop/annotation mutations)
//   placeSearchProvider — Nominatim search suggestions for the stop form

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';

// ---------------------------------------------------------------------------
// MyItinerariesNotifier — list of all itineraries owned by the current user
// ---------------------------------------------------------------------------

class MyItinerariesNotifier extends AsyncNotifier<List<Itinerary>> {
  @override
  Future<List<Itinerary>> build() async {
    return ref.read(itineraryRepositoryProvider).getMyItineraries();
  }

  /// Re-fetch the full list from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(itineraryRepositoryProvider).getMyItineraries(),
    );
  }

  /// Create a new itinerary and prepend it to the list (optimistic).
  Future<Itinerary> addItinerary(Map<String, dynamic> data) async {
    final itinerary =
        await ref.read(itineraryRepositoryProvider).createItinerary(data);
    state.whenData((list) {
      state = AsyncData([itinerary, ...list]);
    });
    return itinerary;
  }

  /// Delete an itinerary and remove it from the list (optimistic).
  Future<void> removeItinerary(String id) async {
    await ref.read(itineraryRepositoryProvider).deleteItinerary(id);
    state.whenData((list) {
      state = AsyncData(list.where((i) => i.id != id).toList());
    });
  }
}

final myItinerariesProvider =
    AsyncNotifierProvider<MyItinerariesNotifier, List<Itinerary>>(
  () => MyItinerariesNotifier(),
);

// ---------------------------------------------------------------------------
// ItineraryDetailNotifier — full detail for one itinerary (family by ID)
// ---------------------------------------------------------------------------
//
// Why FamilyAsyncNotifier?
//   Same reason as followersProvider: one independent Riverpod instance per
//   itinerary ID so opening two different itineraries doesn't share state.
//   The `arg` property gives access to the ID in all methods.

class ItineraryDetailNotifier
    extends FamilyAsyncNotifier<Itinerary, String> {
  @override
  Future<Itinerary> build(String id) {
    return ref.read(itineraryRepositoryProvider).getItinerary(id);
  }

  /// Full re-fetch from the server — used after stop mutations so totals
  /// (total_duration_min, total_cost) reflect the server-recalculated values.
  Future<void> _refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(itineraryRepositoryProvider).getItinerary(arg),
    );
  }

  /// Add a stop, then refresh the full itinerary so totals are accurate.
  Future<void> addStop(Map<String, dynamic> data) async {
    await ref.read(itineraryRepositoryProvider).addStop(arg, data);
    await _refresh();
  }

  /// Update a stop, then refresh.
  Future<void> updateStop(String stopId, Map<String, dynamic> data) async {
    await ref.read(itineraryRepositoryProvider).updateStop(arg, stopId, data);
    await _refresh();
  }

  /// Delete a stop, then refresh.
  Future<void> deleteStop(String stopId) async {
    await ref.read(itineraryRepositoryProvider).deleteStop(arg, stopId);
    await _refresh();
  }

  /// Reorder stops. The backend returns the updated ItineraryDetail, so we
  /// replace state directly without a second fetch.
  Future<void> reorderStops(List<String> stopIds) async {
    final itinerary = await ref
        .read(itineraryRepositoryProvider)
        .reorderStops(arg, stopIds);
    state = AsyncData(itinerary);
  }

  /// Add an annotation and update local state without a full refresh —
  /// annotations don't affect itinerary totals.
  Future<void> addAnnotation(String stopId, Map<String, dynamic> data) async {
    final annotation = await ref
        .read(itineraryRepositoryProvider)
        .addAnnotation(arg, stopId, data);

    state.whenData((itinerary) {
      final updatedStops = itinerary.stops.map((s) {
        if (s.id == stopId) {
          return s.copyWith(annotations: [...s.annotations, annotation]);
        }
        return s;
      }).toList();
      state = AsyncData(itinerary.copyWith(stops: updatedStops));
    });
  }

  /// Update itinerary header fields (title, description, etc.) via PATCH.
  /// Returns the updated Itinerary so callers can redirect if needed.
  Future<Itinerary> updateHeader(Map<String, dynamic> data) async {
    final updated = await ref
        .read(itineraryRepositoryProvider)
        .updateItinerary(arg, data);
    state.whenData((current) {
      state = AsyncData(current.copyWith(
        title: updated.title,
        isPublic: updated.isPublic,
        currency: updated.currency,
        safetyRating: updated.safetyRating,
      ));
    });
    return updated;
  }

  /// Delete an annotation and remove it from local state.
  Future<void> deleteAnnotation(
    String stopId,
    String annotationId,
  ) async {
    await ref
        .read(itineraryRepositoryProvider)
        .deleteAnnotation(arg, stopId, annotationId);

    state.whenData((itinerary) {
      final updatedStops = itinerary.stops.map((s) {
        if (s.id == stopId) {
          return s.copyWith(
            annotations:
                s.annotations.where((a) => a.id != annotationId).toList(),
          );
        }
        return s;
      }).toList();
      state = AsyncData(itinerary.copyWith(stops: updatedStops));
    });
  }
}

final itineraryDetailProvider =
    AsyncNotifierProviderFamily<ItineraryDetailNotifier, Itinerary, String>(
  () => ItineraryDetailNotifier(),
);

// ---------------------------------------------------------------------------
// PlaceSearchNotifier — Nominatim suggestions for the stop form search field
// ---------------------------------------------------------------------------

class PlaceSearchNotifier extends AsyncNotifier<List<PlaceSuggestion>> {
  @override
  Future<List<PlaceSuggestion>> build() async {
    // Start empty — no search has been performed yet.
    return [];
  }

  /// Perform a Nominatim search and replace the suggestion list.
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(geocodingServiceProvider).search(query),
    );
  }

  /// Clear suggestions (e.g. after the user selects one).
  void clear() {
    state = const AsyncData([]);
  }
}

final placeSearchProvider =
    AsyncNotifierProvider<PlaceSearchNotifier, List<PlaceSuggestion>>(
  () => PlaceSearchNotifier(),
);
