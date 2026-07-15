// features/itineraries/providers/saved_itineraries_provider.dart
//
// State for the "Saved" (bookmark) feature:
//   savedItinerariesProvider — the current user's saved itineraries, newest first
//   isItinerarySavedProvider — derived membership flag, single source of truth
//                              for the bookmark toggle on the detail screen
//
// The toggle button reads its filled/outline state from isItinerarySavedProvider
// rather than a field on the Itinerary model, so the Saved tab and the button
// can never disagree, and the state survives offline from the cached list.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';

class SavedItinerariesNotifier extends AsyncNotifier<List<Itinerary>> {
  @override
  Future<List<Itinerary>> build() async {
    return ref.read(itineraryRepositoryProvider).getSavedItineraries();
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getSavedItineraries(forceRefresh: true),
    );
  }

  /// Save an itinerary. Optimistically prepends it so the bookmark fills
  /// instantly, reverts on failure, then warms the offline cache.
  Future<void> save(Itinerary itinerary) async {
    final previous = state.value;
    state.whenData((list) {
      if (list.any((i) => i.id == itinerary.id)) return; // dedupe double-taps
      state = AsyncData([itinerary, ...list]);
    });
    try {
      await ref.read(itineraryRepositoryProvider).saveItinerary(itinerary.id);
    } catch (_) {
      if (previous != null) state = AsyncData(previous); // revert optimistic insert
      rethrow;
    }
    _warmOfflineCache(itinerary.id);
  }

  /// Unsave an itinerary. Optimistically removes it, reverts on failure.
  Future<void> unsave(String id) async {
    final previous = state.value;
    state.whenData((list) {
      state = AsyncData(list.where((i) => i.id != id).toList());
    });
    try {
      await ref.read(itineraryRepositoryProvider).unsaveItinerary(id);
    } catch (_) {
      if (previous != null) state = AsyncData(previous); // revert optimistic removal
      rethrow;
    }
  }

  /// Fire-and-forget: pull the full detail into the Hive cache so the saved
  /// itinerary is browsable offline, then re-fetch the list from the server so
  /// its cached body and saved_at ordering reflect the truth (not just the
  /// optimistic insert). All failures are swallowed — this is best-effort.
  void _warmOfflineCache(String id) {
    unawaited(_warmDetail(id));
    unawaited(_resyncFromServer());
  }

  Future<void> _warmDetail(String id) async {
    try {
      await ref.read(itineraryRepositoryProvider).getItinerary(id);
    } catch (_) {/* best-effort cache warm */}
  }

  Future<void> _resyncFromServer() async {
    try {
      final list = await ref
          .read(itineraryRepositoryProvider)
          .getSavedItineraries(forceRefresh: true);
      state = AsyncData(list);
    } catch (_) {/* keep optimistic state on failure */}
  }
}

final savedItinerariesProvider =
    AsyncNotifierProvider<SavedItinerariesNotifier, List<Itinerary>>(
  () => SavedItinerariesNotifier(),
);

/// Whether the given itinerary is in the current user's saved list.
/// Defaults to false while the list is loading or errored — safe, because the
/// save endpoint is idempotent.
final isItinerarySavedProvider = Provider.family<bool, String>((ref, id) {
  return ref.watch(savedItinerariesProvider).value?.any((i) => i.id == id) ??
      false;
});
