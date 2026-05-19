// test/providers/itinerary_detail_mutations_test.dart — Riverpod tests for
// ItineraryDetailNotifier's addStop, updateStop, and deleteStop methods.
//
// Complements itinerary_detail_notifier_test.dart (which covers moveStop and
// applyReorder). Uses the same fake-repository pattern established there.

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

class _FakeRepo extends ItineraryRepository {
  _FakeRepo() : super(Dio());

  Itinerary itineraryToReturn = _makeItinerary();
  Stop stopToReturn = _makeStop();

  final List<String> getItineraryCalls = [];
  final List<_AddStopCall> addStopCalls = [];
  final List<_UpdateStopCall> updateStopCalls = [];
  final List<_DeleteStopCall> deleteStopCalls = [];

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    getItineraryCalls.add(id);
    return itineraryToReturn;
  }

  @override
  Future<Stop> addStop(
    String itineraryId,
    Map<String, dynamic> data, {
    required String etag,
  }) async {
    addStopCalls.add(_AddStopCall(
      itineraryId: itineraryId,
      body: data,
      etag: etag,
    ));
    return stopToReturn;
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
  Future<void> deleteStop(
    String itineraryId,
    String stopId, {
    required String etag,
  }) async {
    deleteStopCalls.add(_DeleteStopCall(
      itineraryId: itineraryId,
      stopId: stopId,
      etag: etag,
    ));
  }
}

class _AddStopCall {
  final String itineraryId;
  final Map<String, dynamic> body;
  final String etag;
  _AddStopCall(
      {required this.itineraryId, required this.body, required this.etag});
}

class _UpdateStopCall {
  final String itineraryId;
  final String stopId;
  final Map<String, dynamic> body;
  final String etag;
  _UpdateStopCall(
      {required this.itineraryId,
      required this.stopId,
      required this.body,
      required this.etag});
}

class _DeleteStopCall {
  final String itineraryId;
  final String stopId;
  final String etag;
  _DeleteStopCall(
      {required this.itineraryId, required this.stopId, required this.etag});
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

Stop _makeStop() => Stop(
      id: _stopId,
      itineraryId: _itinId,
      trackId: 't1',
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
// Helpers
// ---------------------------------------------------------------------------

Future<ItineraryDetailNotifier> _readyNotifier(
    ProviderContainer container) async {
  await container.read(itineraryDetailProvider(_itinId).future);
  return container.read(itineraryDetailProvider(_itinId).notifier);
}

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

  group('ItineraryDetailNotifier.addStop', () {
    test('Given stop data, passes itinerary ID and data to the repository',
        () async {
      final notifier = await _readyNotifier(container);
      final data = {'place_name': 'Lyon', 'track_id': 't1'};

      await notifier.addStop(data);

      expect(fakeRepo.addStopCalls, hasLength(1));
      final call = fakeRepo.addStopCalls.single;
      expect(call.itineraryId, _itinId);
      expect(call.body, data);
    });

    test('Threads the current ETag into the repository call', () async {
      fakeRepo.itineraryToReturn = _makeItinerary(
        updatedAt: DateTime.utc(2026, 5, 11, 10, 22, 56),
      );
      final expectedEtag =
          '"${DateTime.utc(2026, 5, 11, 10, 22, 56).toIso8601String()}"';

      final notifier = await _readyNotifier(container);
      await notifier.addStop({'place_name': 'Lyon'});

      expect(fakeRepo.addStopCalls.single.etag, expectedEtag);
    });

    test('Refreshes after a successful add', () async {
      final notifier = await _readyNotifier(container);
      expect(fakeRepo.getItineraryCalls, hasLength(1));

      await notifier.addStop({'place_name': 'Lyon'});

      expect(fakeRepo.getItineraryCalls, hasLength(2));
    });
  });

  group('ItineraryDetailNotifier.updateStop', () {
    test('Passes stopId and data to the repository', () async {
      final notifier = await _readyNotifier(container);
      final data = {'place_name': 'Marseille'};

      await notifier.updateStop(_stopId, data);

      expect(fakeRepo.updateStopCalls, hasLength(1));
      final call = fakeRepo.updateStopCalls.single;
      expect(call.itineraryId, _itinId);
      expect(call.stopId, _stopId);
      expect(call.body, data);
    });

    test('Threads the current ETag into the repository call', () async {
      fakeRepo.itineraryToReturn = _makeItinerary(
        updatedAt: DateTime.utc(2026, 5, 11, 10, 22, 56),
      );
      final expectedEtag =
          '"${DateTime.utc(2026, 5, 11, 10, 22, 56).toIso8601String()}"';

      final notifier = await _readyNotifier(container);
      await notifier.updateStop(_stopId, {'place_name': 'Nice'});

      expect(fakeRepo.updateStopCalls.single.etag, expectedEtag);
    });

    test('Refreshes after a successful update', () async {
      final notifier = await _readyNotifier(container);
      expect(fakeRepo.getItineraryCalls, hasLength(1));

      await notifier.updateStop(_stopId, {'place_name': 'Nice'});

      expect(fakeRepo.getItineraryCalls, hasLength(2));
    });
  });

  group('ItineraryDetailNotifier.deleteStop', () {
    test('Passes itinerary ID and stopId to the repository', () async {
      final notifier = await _readyNotifier(container);

      await notifier.deleteStop(_stopId);

      expect(fakeRepo.deleteStopCalls, hasLength(1));
      final call = fakeRepo.deleteStopCalls.single;
      expect(call.itineraryId, _itinId);
      expect(call.stopId, _stopId);
    });

    test('Threads the current ETag into the repository call', () async {
      fakeRepo.itineraryToReturn = _makeItinerary(
        updatedAt: DateTime.utc(2026, 5, 11, 10, 22, 56),
      );
      final expectedEtag =
          '"${DateTime.utc(2026, 5, 11, 10, 22, 56).toIso8601String()}"';

      final notifier = await _readyNotifier(container);
      await notifier.deleteStop(_stopId);

      expect(fakeRepo.deleteStopCalls.single.etag, expectedEtag);
    });

    test('Refreshes after a successful delete', () async {
      final notifier = await _readyNotifier(container);
      expect(fakeRepo.getItineraryCalls, hasLength(1));

      await notifier.deleteStop(_stopId);

      expect(fakeRepo.getItineraryCalls, hasLength(2));
    });
  });
}
