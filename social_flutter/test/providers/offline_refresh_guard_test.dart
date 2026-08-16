// test/providers/offline_refresh_guard_test.dart — verifies that notifier
// `.refresh()` is a no-op while offline: no repository call, and the cached
// AsyncData state stays visible (never AsyncLoading/AsyncError).
//
// Why this matters: pull-to-refresh offline used to flip AsyncData →
// AsyncError, hiding content the HTTP cache still had. The guard
// (isOnlineNowRef in each refresh()) keeps cached data on screen; the shell
// banner explains why nothing refreshed.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeItineraryRepo extends ItineraryRepository {
  _FakeItineraryRepo() : super(Dio());

  final List<bool> getMyItinerariesCalls = [];
  final List<bool> getSharedWithMeCalls = [];
  final List<bool> getItineraryCalls = [];

  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async {
    getMyItinerariesCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<List<FeedItem>> getSharedWithMe({bool forceRefresh = false}) async {
    getSharedWithMeCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    getItineraryCalls.add(forceRefresh);
    return _makeItinerary();
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _itinId = 'itin-1';

Itinerary _makeItinerary() {
  final ts = DateTime.utc(2026, 5, 11, 10, 22, 56);
  return Itinerary(
    id: _itinId,
    userId: 'user-1',
    title: 'Trip',
    totalDurationMin: 0,
    totalCost: 0.0,
    currency: 'EUR',
    visibility: ItineraryVisibility.onlyMe,
    createdAt: ts,
    updatedAt: ts,
  );
}

ProviderContainer _makeContainer(_FakeItineraryRepo repo,
    {required bool online}) {
  return ProviderContainer(overrides: [
    itineraryRepositoryProvider.overrideWithValue(repo),
    isOnlineProvider.overrideWith((ref) => Stream.value(online)),
  ]);
}

/// StreamProviders only consume their stream while actively listened — a bare
/// `read(.future)` in a plain test never resolves. Subscribe, then await the
/// first emission so the guard's sync read sees the overridden value.
Future<void> _settleConnectivity(ProviderContainer container) async {
  final sub = container.listen(isOnlineProvider, (_, _) {});
  addTearDown(sub.close);
  await container.read(isOnlineProvider.future);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Notifier .refresh() offline guard', () {
    test(
        'Given the device is offline, '
        'When MyItinerariesNotifier.refresh() is called, '
        'Then no repository call fires and cached AsyncData is preserved',
        () async {
      final repo = _FakeItineraryRepo();
      final container = _makeContainer(repo, online: false);
      addTearDown(container.dispose);

      await container.read(myItinerariesProvider.future); // initial build
      // Let the connectivity stream emit so the guard reads false, not the
      // optimistic pre-seed default.
      await _settleConnectivity(container);

      await container.read(myItinerariesProvider.notifier).refresh();

      expect(repo.getMyItinerariesCalls, [false]); // build only, no refresh
      final state = container.read(myItinerariesProvider);
      expect(state.hasValue, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test(
        'Given the device is offline, '
        'When SharedWithMeNotifier.refresh() is called, '
        'Then no repository call fires and cached AsyncData is preserved',
        () async {
      final repo = _FakeItineraryRepo();
      final container = _makeContainer(repo, online: false);
      addTearDown(container.dispose);

      await container.read(sharedWithMeProvider.future);
      await _settleConnectivity(container);

      await container.read(sharedWithMeProvider.notifier).refresh();

      expect(repo.getSharedWithMeCalls, [false]); // build only, no refresh
      final state = container.read(sharedWithMeProvider);
      expect(state.hasValue, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test(
        'Given the device is offline, '
        'When ItineraryDetailNotifier.refresh() is called, '
        'Then no repository call fires and cached AsyncData is preserved',
        () async {
      final repo = _FakeItineraryRepo();
      final container = _makeContainer(repo, online: false);
      addTearDown(container.dispose);

      await container.read(itineraryDetailProvider(_itinId).future);
      await _settleConnectivity(container);

      await container.read(itineraryDetailProvider(_itinId).notifier).refresh();

      expect(repo.getItineraryCalls, [false]);
      final state = container.read(itineraryDetailProvider(_itinId));
      expect(state.hasValue, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test(
        'Given the device is online, '
        'When MyItinerariesNotifier.refresh() is called, '
        'Then the forced refresh fires as before', () async {
      final repo = _FakeItineraryRepo();
      final container = _makeContainer(repo, online: true);
      addTearDown(container.dispose);

      await container.read(myItinerariesProvider.future);
      await _settleConnectivity(container);

      await container.read(myItinerariesProvider.notifier).refresh();

      expect(repo.getMyItinerariesCalls, [false, true]);
    });
  });
}
