// features/itineraries/providers/itinerary_providers.dart — Riverpod state management.
//
// Providers:
//   myItinerariesProvider      — list of current user's itineraries
//   itineraryDetailProvider    — full detail for one itinerary (family by ID)
//   allowedUsersProvider       — restricted allowlist for one itinerary (family by ID)
//   placeSearchProvider        — Nominatim suggestions for the stop form
//   mapPlaceSearchProvider     — Nominatim suggestions for the map picker

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/data/maps_launcher_service.dart';
import 'package:social_flutter/features/itineraries/data/share_service.dart';
import 'package:social_flutter/features/itineraries/domain/allowed_user.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/my_rating.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';

// ---------------------------------------------------------------------------
// MyItinerariesNotifier
// ---------------------------------------------------------------------------

class MyItinerariesNotifier extends AsyncNotifier<List<Itinerary>> {
  @override
  Future<List<Itinerary>> build() async {
    return ref.read(itineraryRepositoryProvider).getMyItineraries();
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getMyItineraries(forceRefresh: true),
    );
  }

  Future<Itinerary> addItinerary(Map<String, dynamic> data) async {
    final itinerary = await ref
        .read(itineraryRepositoryProvider)
        .createItinerary(data);
    state.whenData((list) {
      state = AsyncData([itinerary, ...list]);
    });
    return itinerary;
  }

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
// ItineraryDetailNotifier
// ---------------------------------------------------------------------------

class ItineraryDetailNotifier extends AsyncNotifier<Itinerary> {
  // Riverpod 3 removed FamilyAsyncNotifier; the family argument (itinerary id)
  // now arrives via the constructor and is kept in `arg` so method bodies below
  // read identically to the pre-migration code.
  ItineraryDetailNotifier(this.arg);
  final String arg;

  @override
  Future<Itinerary> build() {
    return ref.read(itineraryRepositoryProvider).getItinerary(arg);
  }

  /// Current ETag for the If-Match header on every mutation.
  ///
  /// Reads the itinerary's updatedAt from the currently loaded state and
  /// formats it as a quoted RFC 7232 string, e.g. '"2026-05-07T14:23:11Z"'.
  ///
  /// Returns '' if state is not yet loaded (AsyncLoading / AsyncError). In
  /// practice this shouldn't happen because the user has to view the itinerary
  /// detail screen (which loads state) before any mutation is possible. If it
  /// does happen the server returns 412 / ItineraryStaleException which prompts
  /// a reload — a safe fallback.
  String get _etag => state.value?.eTag ?? '';

  /// Full re-fetch from the server.
  /// Called after every mutation so totals and track structure are up-to-date,
  /// and by RefreshIndicator on the detail screen. Forces a fresh server fetch
  /// (bypasses the cache validator) so a 304 with a stale local body can't
  /// silently no-op a pull-to-refresh.
  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getItinerary(arg, forceRefresh: true),
    );
  }

  /// Add a stop, then refresh so totals and track structure are accurate.
  /// The ETag is attached automatically via _etag — the presentation layer
  /// does not need to know about concurrency control.
  Future<void> addStop(Map<String, dynamic> data) async {
    await ref.read(itineraryRepositoryProvider).addStop(arg, data, etag: _etag);
    await refresh();
  }

  /// Update a stop, then refresh.
  Future<void> updateStop(String stopId, Map<String, dynamic> data) async {
    await ref
        .read(itineraryRepositoryProvider)
        .updateStop(arg, stopId, data, etag: _etag);
    await refresh();
  }

  /// Commit a batch reorder in one server transaction.
  ///
  /// At least one of [stopOrders], [trackOrder], or [segmentIdsToDelete] must
  /// be provided. The server validates set-equality (for stop_orders and
  /// track_order), recomputes fractional-index ranks, deletes any requested
  /// segments, and returns the full updated itinerary. A `refresh()` after
  /// the call adopts the server-confirmed state locally.
  Future<void> applyReorder({
    Map<String, List<String>>? stopOrders,
    List<String>? trackOrder,
    List<String>? segmentIdsToDelete,
  }) async {
    await ref
        .read(itineraryRepositoryProvider)
        .reorderItinerary(
          arg,
          stopOrders: stopOrders,
          trackOrder: trackOrder,
          segmentIdsToDelete: segmentIdsToDelete,
          etag: _etag,
        );
    await refresh();
  }

  /// Move a stop to a new position.
  ///
  /// Three move modes, mutually exclusive:
  ///   1. Within-track reorder: pass [afterStopId] / [beforeStopId] only.
  ///   2. Cross-track move into an existing track: pass [targetTrackId].
  ///   3. New-track move: pass [afterTrackId] and/or [beforeTrackId]
  ///      (with [targetTrackId] null). Server creates a brand-new track at
  ///      that position and moves this stop into it as the sole member.
  ///
  /// Bumps the ETag and refreshes the local state. Returns the moved [Stop]
  /// so callers can read its (possibly newly created) `trackId`.
  Future<Stop> moveStop(
    String stopId, {
    String? afterStopId,
    String? beforeStopId,
    String? targetTrackId,
    String? afterTrackId,
    String? beforeTrackId,
  }) async {
    final body = <String, dynamic>{
      if (afterStopId != null) 'after_stop_id': afterStopId,
      if (beforeStopId != null) 'before_stop_id': beforeStopId,
      if (targetTrackId != null) 'track_id': targetTrackId,
      if (afterTrackId != null) 'after_track_id': afterTrackId,
      if (beforeTrackId != null) 'before_track_id': beforeTrackId,
    };
    final updated = await ref
        .read(itineraryRepositoryProvider)
        .updateStop(arg, stopId, body, etag: _etag);
    await refresh();
    return updated;
  }

  /// Delete a stop, then refresh.
  Future<void> deleteStop(String stopId) async {
    await ref
        .read(itineraryRepositoryProvider)
        .deleteStop(arg, stopId, etag: _etag);
    await refresh();
  }

  /// Update itinerary header fields.
  Future<Itinerary> updateHeader(Map<String, dynamic> data) async {
    final updated = await ref
        .read(itineraryRepositoryProvider)
        .updateItinerary(arg, data);
    state.whenData((current) {
      // The PATCH response is an ItinerarySummary, which omits `description`, so
      // `updated.description` is always null — adopt the just-saved value from the
      // request payload instead (the server stored it verbatim). Absent key means
      // the caller didn't touch the description, so keep the current one.
      final descProvided = data.containsKey('description');
      final newDescription =
          descProvided ? data['description'] as String? : current.description;
      state = AsyncData(
        current.copyWith(
          title: updated.title,
          description: newDescription,
          clearDescription: descProvided && newDescription == null,
          visibility: updated.visibility,
          currency: updated.currency,
          updatedAt: updated.updatedAt,
          // Cover image is deleted/uploaded BEFORE this PATCH, so the response
          // carries the authoritative URL — adopt it (clearing when removed) so
          // stale covers don't linger after a remove.
          coverImageUrl: updated.coverImageUrl,
          clearCoverImageUrl: updated.coverImageUrl == null,
        ),
      );
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
    await ref.read(itineraryRepositoryProvider).deleteSegment(arg, segmentId);
    await refresh();
  }

  /// Add a stop-level annotation, then refresh.
  Future<void> addAnnotation(String stopId, Map<String, dynamic> data) async {
    await ref
        .read(itineraryRepositoryProvider)
        .addAnnotation(arg, stopId, data, etag: _etag);
    await refresh();
  }

  /// Update a stop-level annotation, then refresh.
  Future<void> updateAnnotation(
    String stopId,
    String annotationId, {
    String? content,
    AnnotationType? type,
  }) async {
    await ref
        .read(itineraryRepositoryProvider)
        .updateAnnotation(
          arg,
          stopId,
          annotationId,
          content: content,
          type: type,
          etag: _etag,
        );
    await refresh();
  }

  /// Delete a stop-level annotation, then refresh.
  Future<void> deleteAnnotation(String stopId, String annotationId) async {
    await ref
        .read(itineraryRepositoryProvider)
        .deleteAnnotation(arg, stopId, annotationId, etag: _etag);
    await refresh();
  }

  /// Add an itinerary-level annotation, then refresh.
  Future<void> addItineraryAnnotation(Map<String, dynamic> data) async {
    await ref
        .read(itineraryRepositoryProvider)
        .addItineraryAnnotation(arg, data, etag: _etag);
    await refresh();
  }

  /// Update an itinerary-level annotation, then refresh.
  Future<void> updateItineraryAnnotation(
    String annotationId, {
    String? content,
    AnnotationType? type,
  }) async {
    await ref
        .read(itineraryRepositoryProvider)
        .updateItineraryAnnotation(
          arg,
          annotationId,
          content: content,
          type: type,
          etag: _etag,
        );
    await refresh();
  }

  /// Delete an itinerary-level annotation, then refresh.
  Future<void> deleteItineraryAnnotation(String annotationId) async {
    await ref
        .read(itineraryRepositoryProvider)
        .deleteItineraryAnnotation(arg, annotationId, etag: _etag);
    await refresh();
  }
}

final itineraryDetailProvider =
    AsyncNotifierProvider.family<ItineraryDetailNotifier, Itinerary, String>(
      ItineraryDetailNotifier.new,
    );

// ---------------------------------------------------------------------------
// AllowedUsersNotifier
// ---------------------------------------------------------------------------

class AllowedUsersNotifier extends AsyncNotifier<List<AllowedUser>> {
  AllowedUsersNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<List<AllowedUser>> build() {
    return ref.read(itineraryRepositoryProvider).getAllowedUsers(arg);
  }

  Future<void> addUser(String userId) async {
    final added = await ref
        .read(itineraryRepositoryProvider)
        .addAllowedUser(arg, userId);
    state.whenData((list) {
      state = AsyncData([...list, added]);
    });
  }

  Future<void> removeUser(String userId) async {
    await ref.read(itineraryRepositoryProvider).removeAllowedUser(arg, userId);
    state.whenData((list) {
      state = AsyncData(list.where((u) => u.userId != userId).toList());
    });
  }
}

final allowedUsersProvider = AsyncNotifierProvider.family<
  AllowedUsersNotifier,
  List<AllowedUser>,
  String
>(AllowedUsersNotifier.new);

// ---------------------------------------------------------------------------
// UserItinerariesNotifier
// ---------------------------------------------------------------------------

class UserItinerariesNotifier extends AsyncNotifier<List<Itinerary>> {
  UserItinerariesNotifier(this.arg); // family argument: user id
  final String arg;

  @override
  Future<List<Itinerary>> build() {
    return ref.read(itineraryRepositoryProvider).getUserItineraries(arg);
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getUserItineraries(arg, forceRefresh: true),
    );
  }
}

final userItinerariesProvider = AsyncNotifierProvider.family<
  UserItinerariesNotifier,
  List<Itinerary>,
  String
>(UserItinerariesNotifier.new);

// ---------------------------------------------------------------------------
// MyRatingNotifier
// ---------------------------------------------------------------------------

class MyRatingNotifier extends AsyncNotifier<MyRating?> {
  MyRatingNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<MyRating?> build() {
    return ref.read(itineraryRepositoryProvider).getMyRating(arg);
  }

  Future<void> submitRating(MyRating rating) async {
    final saved = await ref
        .read(itineraryRepositoryProvider)
        .submitRating(arg, rating);
    state = AsyncData(saved);
    await ref.read(itineraryDetailProvider(arg).notifier).refresh();
  }

  Future<void> deleteRating() async {
    await ref.read(itineraryRepositoryProvider).deleteMyRating(arg);
    state = const AsyncData(null);
    await ref.read(itineraryDetailProvider(arg).notifier).refresh();
  }
}

final myRatingProvider =
    AsyncNotifierProvider.family<MyRatingNotifier, MyRating?, String>(
      MyRatingNotifier.new,
    );

// ---------------------------------------------------------------------------
// RatingsPageNotifier
// ---------------------------------------------------------------------------

class RatingsPageNotifier extends AsyncNotifier<RatingsPage> {
  RatingsPageNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<RatingsPage> build() {
    return ref.read(itineraryRepositoryProvider).getRatingsPage(arg);
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getRatingsPage(arg, forceRefresh: true),
    );
  }
}

final ratingsPageProvider =
    AsyncNotifierProvider.family<RatingsPageNotifier, RatingsPage, String>(
      RatingsPageNotifier.new,
    );

// ---------------------------------------------------------------------------
// PlaceSearchNotifier
// ---------------------------------------------------------------------------

class PlaceSearchNotifier extends AsyncNotifier<List<PlaceSuggestion>> {
  @override
  Future<List<PlaceSuggestion>> build() async => [];

  /// [near] biases results toward that point and sorts them nearest-first
  /// (see GeocodingService.search).
  Future<void> search(String query, {LatLng? near}) async {
    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(geocodingServiceProvider)
          .search(
            query,
            languageCode: ref.read(localeProvider).languageCode,
            near: near,
          ),
    );
  }

  void clear() {
    state = const AsyncData([]);
  }
}

final placeSearchProvider =
    AsyncNotifierProvider<PlaceSearchNotifier, List<PlaceSuggestion>>(
      () => PlaceSearchNotifier(),
    );

/// Separate instance for the map picker — the stop form (beneath it in the
/// navigator stack) watches [placeSearchProvider]; sharing one would leak the
/// picker's results into the form's inline suggestion list on return.
final mapPlaceSearchProvider =
    AsyncNotifierProvider<PlaceSearchNotifier, List<PlaceSuggestion>>(
      () => PlaceSearchNotifier(),
    );

// ---------------------------------------------------------------------------
// ShareService provider
// ---------------------------------------------------------------------------

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

// ---------------------------------------------------------------------------
// MapsLauncherService provider
// ---------------------------------------------------------------------------

final mapsLauncherServiceProvider = Provider<MapsLauncherService>(
  (ref) => MapsLauncherService(),
);
