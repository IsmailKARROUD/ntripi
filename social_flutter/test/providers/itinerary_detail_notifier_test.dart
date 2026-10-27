// test/providers/itinerary_detail_notifier_test.dart — Riverpod notifier tests
// for ItineraryDetailNotifier's arrange-mode save.
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
//   - Every save answers with the whole trip, which is adopted: no reload.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/trip_edit_answer.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Subclass override — overrides only what the notifier under test calls.
/// Unstubbed methods would hit the real (dummy) Dio and explode; the tests
/// here keep the surface area small enough that this is fine.
class _FakeRepo extends ItineraryRepository {
  _FakeRepo() : super(Dio());

  Itinerary itineraryToReturn = _makeItinerary();

  /// The trip every save answers with.
  Itinerary answeredTrip = _tripWith(_makeStop());

  // Call recorders.
  final List<String> getItineraryCalls = [];
  final List<_ReorderCall> reorderCalls = [];

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    getItineraryCalls.add(id);
    return itineraryToReturn;
  }

  @override
  Future<TripEditAnswer> reorderItinerary(
    String itineraryId, {
    required List<Map<String, dynamic>> layout,
    List<String>? segmentIdsToDelete,
    required String etag,
    required String? lockToken,
  }) async {
    reorderCalls.add(_ReorderCall(
      itineraryId: itineraryId,
      layout: layout,
      segmentIdsToDelete: segmentIdsToDelete,
      etag: etag,
    ));
    return TripEditAnswer(answeredTrip);
  }
}

class _ReorderCall {
  final String itineraryId;
  final List<Map<String, dynamic>> layout;
  final List<String>? segmentIdsToDelete;
  final String etag;
  _ReorderCall({
    required this.itineraryId,
    required this.layout,
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

/// A trip answered after a save: a later stamp, [stop] on its own track.
Itinerary _tripWith(Stop stop) => _makeItinerary(
      updatedAt: DateTime.utc(2026, 5, 11, 10, 23, 30),
    ).copyWith(tracks: [
      Track(id: stop.trackId, itineraryId: _itinId, rank: 'a0', stops: [stop]),
    ]);

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

  group('ItineraryDetailNotifier.applyArrangement', () {
    const layout = [
      {
        'track_id': 't2',
        'stop_ids': ['stop-1', 'stop-2'],
      },
      {
        'track_id': null,
        'stop_ids': ['stop-3'],
      },
    ];

    test('forwards the layout and the segments it breaks', () async {
      final notifier = await _readyNotifier();

      await notifier.applyArrangement(
        layout: layout,
        segmentIdsToDelete: ['seg-1'],
      );

      expect(fakeRepo.reorderCalls, hasLength(1));
      final call = fakeRepo.reorderCalls.single;
      expect(call.layout, layout);
      expect(call.segmentIdsToDelete, ['seg-1']);
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
      await notifier.applyArrangement(layout: layout);

      expect(fakeRepo.reorderCalls.single.etag, expectedEtag);
      expect(fakeRepo.reorderCalls.single.segmentIdsToDelete, isNull);
    });

    test('adopts the answered trip, without a reload', () async {
      final notifier = await _readyNotifier();
      // Initial build → 1 getItinerary call, and no other after the save.
      expect(fakeRepo.getItineraryCalls, hasLength(1));

      await notifier.applyArrangement(layout: layout);

      expect(fakeRepo.getItineraryCalls, hasLength(1));
      expect(container.read(itineraryDetailProvider(_itinId)).value,
          same(fakeRepo.answeredTrip));
    });
  });
}
