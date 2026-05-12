// test/providers/itinerary_detail_notifier_test.dart — Riverpod notifier tests
// for ItineraryDetailNotifier's reorder-related methods.
//
// First Riverpod-based test in the project; establishes the
// ProviderContainer + fake-repository pattern.
//
// Strategy:
//   - Subclass ItineraryRepository (a plain concrete class) and override only
//     the methods the notifier exercises. Pass a dummy Dio() to super(...).
//   - Wire the fake into a ProviderContainer via
//     itineraryRepositoryProvider.overrideWithValue(...).
//   - Wait for build() to complete via `container.read(provider.future)` before
//     invoking mutating methods.
//   - Capture call args on the fake to assert body shape + ETag threading.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Subclass override — overrides only what the notifier under test calls.
/// Unstubbed methods would hit the real (dummy) Dio and explode; the tests
/// here keep the surface area small enough that this is fine.
class _FakeRepo extends ItineraryRepository {
  _FakeRepo() : super(Dio());

  Itinerary itineraryToReturn = _makeItinerary();
  Stop stopToReturn = _makeStop();

  // Call recorders.
  final List<String> getItineraryCalls = [];
  final List<_UpdateStopCall> updateStopCalls = [];
  final List<_ReorderCall> reorderCalls = [];

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    getItineraryCalls.add(id);
    return itineraryToReturn;
  }

  @override
  Future<Stop> updateStop(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data, {
    required String etag,
  }) async {
    updateStopCalls.add(_UpdateStopCall(
      itineraryId: itineraryId,
      stopId: stopId,
      body: data,
      etag: etag,
    ));
    return stopToReturn;
  }

  @override
  Future<Itinerary> reorderItinerary(
    String itineraryId, {
    Map<String, List<String>>? stopOrders,
    List<String>? trackOrder,
    List<String>? segmentIdsToDelete,
    required String etag,
  }) async {
    reorderCalls.add(_ReorderCall(
      itineraryId: itineraryId,
      stopOrders: stopOrders,
      trackOrder: trackOrder,
      segmentIdsToDelete: segmentIdsToDelete,
      etag: etag,
    ));
    return itineraryToReturn;
  }
}

class _UpdateStopCall {
  final String itineraryId;
  final String stopId;
  final Map<String, dynamic> body;
  final String etag;
  _UpdateStopCall({
    required this.itineraryId,
    required this.stopId,
    required this.body,
    required this.etag,
  });
}

class _ReorderCall {
  final String itineraryId;
  final Map<String, List<String>>? stopOrders;
  final List<String>? trackOrder;
  final List<String>? segmentIdsToDelete;
  final String etag;
  _ReorderCall({
    required this.itineraryId,
    required this.stopOrders,
    required this.trackOrder,
    required this.segmentIdsToDelete,
    required this.etag,
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _itinId = 'itin-1';
const _stopId = 'stop-1';

Itinerary _makeItinerary({DateTime? updatedAt}) {
  final ts = updatedAt ?? DateTime.utc(2026, 5, 11, 10, 22, 56);
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

Stop _makeStop({String trackId = 't2'}) => Stop(
      id: _stopId,
      itineraryId: _itinId,
      trackId: trackId,
      rank: 'a0',
      placeName: 'Paris',
      placeAddress: null,
      lat: null,
      lng: null,
      placeType: null,
      durationMin: null,
      cost: 0.0,
      isFree: true,
      notes: null,
      type: StopType.waypoint,
      createdAt: DateTime.utc(2026, 5, 11),
      annotations: const [],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeRepo fakeRepo;
  late ProviderContainer container;

  setUp(() {
    fakeRepo = _FakeRepo();
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider.overrideWithValue(fakeRepo),
    ]);
  });

  tearDown(() => container.dispose());

  /// Wait for the family notifier's initial build to resolve, then return its
  /// notifier handle.
  Future<ItineraryDetailNotifier> _readyNotifier() async {
    await container.read(itineraryDetailProvider(_itinId).future);
    return container.read(itineraryDetailProvider(_itinId).notifier);
  }

  group('ItineraryDetailNotifier.moveStop', () {
    test('cross-track move passes track_id and no new-track anchors',
        () async {
      final notifier = await _readyNotifier();

      await notifier.moveStop(_stopId, targetTrackId: 't2');

      expect(fakeRepo.updateStopCalls, hasLength(1));
      final body = fakeRepo.updateStopCalls.single.body;
      expect(body['track_id'], 't2');
      expect(body.containsKey('after_track_id'), isFalse);
      expect(body.containsKey('before_track_id'), isFalse);
    });

    test('new-track move passes after/before anchors and no track_id',
        () async {
      final notifier = await _readyNotifier();

      await notifier.moveStop(
        _stopId,
        afterTrackId: 't1',
        beforeTrackId: 't2',
      );

      final body = fakeRepo.updateStopCalls.single.body;
      expect(body['after_track_id'], 't1');
      expect(body['before_track_id'], 't2');
      expect(body.containsKey('track_id'), isFalse);
    });

    test('returns the moved Stop from the repository', () async {
      fakeRepo.stopToReturn = _makeStop(trackId: 'destination-track');
      final notifier = await _readyNotifier();

      final result = await notifier.moveStop(_stopId, targetTrackId: 't2');

      expect(result.trackId, 'destination-track');
    });

    test('threads the current ETag (quoted ISO timestamp) into If-Match',
        () async {
      // Initial Itinerary has a specific updatedAt → the notifier's _etag
      // getter formats it as the quoted ISO string.
      fakeRepo.itineraryToReturn = _makeItinerary(
        updatedAt: DateTime.utc(2026, 5, 11, 10, 22, 56),
      );
      final expectedEtag =
          '"${DateTime.utc(2026, 5, 11, 10, 22, 56).toIso8601String()}"';

      final notifier = await _readyNotifier();
      await notifier.moveStop(_stopId, targetTrackId: 't2');

      expect(fakeRepo.updateStopCalls.single.etag, expectedEtag);
    });

    test('refresh fires after a successful mutation', () async {
      final notifier = await _readyNotifier();
      // Initial build → 1 getItinerary call. After mutation → 2.
      expect(fakeRepo.getItineraryCalls, hasLength(1));

      await notifier.moveStop(_stopId, targetTrackId: 't2');

      expect(fakeRepo.getItineraryCalls, hasLength(2));
    });
  });

  group('ItineraryDetailNotifier.applyReorder', () {
    test('stop_orders body is forwarded to the repository', () async {
      final notifier = await _readyNotifier();

      await notifier.applyReorder(stopOrders: {
        't1': ['s2', 's1'],
      });

      expect(fakeRepo.reorderCalls, hasLength(1));
      final call = fakeRepo.reorderCalls.single;
      expect(call.stopOrders, {
        't1': ['s2', 's1'],
      });
      expect(call.trackOrder, isNull);
      expect(call.segmentIdsToDelete, isNull);
    });

    test('trackOrder + segmentIdsToDelete forwarded together', () async {
      final notifier = await _readyNotifier();

      await notifier.applyReorder(
        trackOrder: ['t3', 't1', 't2'],
        segmentIdsToDelete: ['seg-1', 'seg-2'],
      );

      final call = fakeRepo.reorderCalls.single;
      expect(call.trackOrder, ['t3', 't1', 't2']);
      expect(call.segmentIdsToDelete, ['seg-1', 'seg-2']);
      expect(call.stopOrders, isNull);
    });

    test('applyReorder with no arguments still calls the repository', () async {
      // Server would 422 in real flow, but the client just passes the empty
      // intent through. Documents the current behavior.
      final notifier = await _readyNotifier();

      await notifier.applyReorder();

      expect(fakeRepo.reorderCalls, hasLength(1));
      final call = fakeRepo.reorderCalls.single;
      expect(call.stopOrders, isNull);
      expect(call.trackOrder, isNull);
      expect(call.segmentIdsToDelete, isNull);
    });

    test('refresh fires after a successful applyReorder', () async {
      final notifier = await _readyNotifier();
      expect(fakeRepo.getItineraryCalls, hasLength(1));

      await notifier.applyReorder(stopOrders: {
        't1': ['s1'],
      });

      expect(fakeRepo.getItineraryCalls, hasLength(2));
    });
  });
}
