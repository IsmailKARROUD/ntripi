// features/itineraries/providers/itinerary_providers.dart — Riverpod state management.
//
// Providers:
//   myItinerariesProvider      — list of current user's itineraries
//   itineraryDetailProvider    — full detail for one itinerary (family by ID)
//   allowedUsersProvider       — restricted allowlist for one itinerary (family by ID)
//   placeSearchProvider        — Nominatim suggestions for the stop form

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/allowed_user.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/my_rating.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';

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

class ItineraryDetailNotifier
    extends FamilyAsyncNotifier<Itinerary, String> {
  @override
  Future<Itinerary> build(String id) {
    return ref.read(itineraryRepositoryProvider).getItinerary(id);
  }

  /// Full re-fetch from the server — used after stop mutations so totals
  /// (total_duration_min, total_cost) reflect the server-recalculated values.
  /// Also called by MyRatingNotifier after a rating change to update rating_avg.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(itineraryRepositoryProvider).getItinerary(arg),
    );
  }

  /// Add a stop, then refresh the full itinerary so totals are accurate.
  Future<void> addStop(Map<String, dynamic> data) async {
    await ref.read(itineraryRepositoryProvider).addStop(arg, data);
    await refresh();
  }

  /// Update a stop, then refresh.
  Future<void> updateStop(String stopId, Map<String, dynamic> data) async {
    await ref.read(itineraryRepositoryProvider).updateStop(arg, stopId, data);
    await refresh();
  }

  /// Delete a stop, then refresh.
  Future<void> deleteStop(String stopId) async {
    await ref.read(itineraryRepositoryProvider).deleteStop(arg, stopId);
    await refresh();
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

  /// Update itinerary header fields (title, description, visibility, etc.).
  /// Returns the updated Itinerary so callers can redirect if needed.
  Future<Itinerary> updateHeader(Map<String, dynamic> data) async {
    final updated = await ref
        .read(itineraryRepositoryProvider)
        .updateItinerary(arg, data);
    state.whenData((current) {
      state = AsyncData(current.copyWith(
        title: updated.title,
        visibility: updated.visibility,
        currency: updated.currency,
      ));
    });
    return updated;
  }

  /// Create a transit segment and refresh.
  Future<void> createSegment(Map<String, dynamic> data) async {
    await ref.read(itineraryRepositoryProvider).createSegment(arg, data);
    await refresh();
  }

  /// Update (replace) a transit segment and refresh.
  Future<void> updateSegment(
    String segmentId,
    Map<String, dynamic> data,
  ) async {
    await ref
        .read(itineraryRepositoryProvider)
        .updateSegment(arg, segmentId, data);
    await refresh();
  }

  /// Delete a transit segment and refresh.
  Future<void> deleteSegment(String segmentId) async {
    await ref
        .read(itineraryRepositoryProvider)
        .deleteSegment(arg, segmentId);
    await refresh();
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
// AllowedUsersNotifier — restricted allowlist for one itinerary (family by ID)
// ---------------------------------------------------------------------------

class AllowedUsersNotifier
    extends FamilyAsyncNotifier<List<AllowedUser>, String> {
  @override
  Future<List<AllowedUser>> build(String itineraryId) {
    return ref.read(itineraryRepositoryProvider).getAllowedUsers(itineraryId);
  }

  /// Add a user to the allowlist and update local state.
  Future<void> addUser(String userId) async {
    final added = await ref
        .read(itineraryRepositoryProvider)
        .addAllowedUser(arg, userId);
    state.whenData((list) {
      state = AsyncData([...list, added]);
    });
  }

  /// Remove a user from the allowlist and update local state.
  Future<void> removeUser(String userId) async {
    await ref
        .read(itineraryRepositoryProvider)
        .removeAllowedUser(arg, userId);
    state.whenData((list) {
      state = AsyncData(list.where((u) => u.userId != userId).toList());
    });
  }
}

final allowedUsersProvider =
    AsyncNotifierProviderFamily<AllowedUsersNotifier, List<AllowedUser>, String>(
  () => AllowedUsersNotifier(),
);

// ---------------------------------------------------------------------------
// UserItinerariesNotifier — itineraries on another user's profile (family by userId)
// ---------------------------------------------------------------------------

class UserItinerariesNotifier
    extends FamilyAsyncNotifier<List<Itinerary>, String> {
  @override
  Future<List<Itinerary>> build(String userId) {
    return ref.read(itineraryRepositoryProvider).getUserItineraries(userId);
  }

  /// Re-fetch from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(itineraryRepositoryProvider).getUserItineraries(arg),
    );
  }
}

final userItinerariesProvider = AsyncNotifierProviderFamily<
    UserItinerariesNotifier, List<Itinerary>, String>(
  () => UserItinerariesNotifier(),
);

// ---------------------------------------------------------------------------
// MyRatingNotifier — current user's star rating for one itinerary (family by ID)
// ---------------------------------------------------------------------------

/// State: the user's current rating, or null if they have not rated.
class MyRatingNotifier extends FamilyAsyncNotifier<MyRating?, String> {
  @override
  Future<MyRating?> build(String itineraryId) {
    return ref.read(itineraryRepositoryProvider).getMyRating(itineraryId);
  }

  /// Submit (or update) the rating and update itinerary aggregate locally.
  Future<void> submitRating(MyRating rating) async {
    final saved = await ref
        .read(itineraryRepositoryProvider)
        .submitRating(arg, rating);
    state = AsyncData(saved);

    // Refresh the detail so rating_avg / rating_count reflect the new value.
    await ref
        .read(itineraryDetailProvider(arg).notifier)
        .refresh();
  }

  /// Delete the rating and clear local state.
  Future<void> deleteRating() async {
    await ref.read(itineraryRepositoryProvider).deleteMyRating(arg);
    state = const AsyncData(null);

    await ref
        .read(itineraryDetailProvider(arg).notifier)
        .refresh();
  }
}

final myRatingProvider =
    AsyncNotifierProviderFamily<MyRatingNotifier, MyRating?, String>(
  () => MyRatingNotifier(),
);

// ---------------------------------------------------------------------------
// RatingsPageNotifier — full ratings page for one itinerary (family by ID)
// ---------------------------------------------------------------------------

class RatingsPageNotifier extends FamilyAsyncNotifier<RatingsPage, String> {
  @override
  Future<RatingsPage> build(String itineraryId) {
    return ref.read(itineraryRepositoryProvider).getRatingsPage(itineraryId);
  }

  /// Re-fetch from the server — called after a rating is submitted or deleted.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(itineraryRepositoryProvider).getRatingsPage(arg),
    );
  }
}

final ratingsPageProvider =
    AsyncNotifierProviderFamily<RatingsPageNotifier, RatingsPage, String>(
  () => RatingsPageNotifier(),
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
