// test/providers/itinerary_writes_in_flight_test.dart — what leaving edit mode
// waits on.
//
// Every write that carries this device's edit claim runs through one wrapper in
// ItineraryDetailNotifier, which counts it until it and its refresh are done.
// ✓ and Back wait on writesSettled(): handing the claim back under a running
// write made the server refuse it, after the card showing its spinner had gone.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

const _itinId = 'itin-1';

/// Holds every segment write — and, when asked, the refresh after it — open
/// until the test answers it.
class _GatedRepo extends ItineraryRepository {
  _GatedRepo() : super(Dio());

  final writes = <Completer<void>>[];
  final lockTokens = <String?>[];

  /// Set to hold the next refresh open; the first load is never held.
  Completer<void>? refreshGate;
  int loads = 0;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    loads++;
    if (loads > 1) await refreshGate?.future;
    final ts = DateTime.utc(2026, 10, 10);
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

  Future<void> _held(String? lockToken) {
    lockTokens.add(lockToken);
    final gate = Completer<void>();
    writes.add(gate);
    return gate.future;
  }

  @override
  Future<TransitSegment> updateSegment(
    String itineraryId,
    String segmentId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) async {
    await _held(lockToken);
    return TransitSegment(
      id: segmentId,
      itineraryId: itineraryId,
      fromStopId: 'stop-1',
      toStopId: 'stop-2',
      totalDurationMin: 0,
      totalCost: 0.0,
      createdAt: DateTime.utc(2026, 10, 10),
    );
  }

  @override
  Future<void> deleteSegment(
    String itineraryId,
    String segmentId, {
    required String etag,
    required String? lockToken,
  }) =>
      _held(lockToken);
}

/// A claim held by this device, without the network or the heartbeat.
class _HeldClaim extends EditLockNotifier {
  _HeldClaim(super.arg);

  @override
  EditSession build() {
    super.build();
    return const EditSession(token: 'lock-token');
  }
}

/// Lets a started write reach its gate.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _GatedRepo repo;
  late ProviderContainer container;
  late ItineraryDetailNotifier notifier;

  setUp(() async {
    repo = _GatedRepo();
    container = ProviderContainer(overrides: [
      itineraryRepositoryProvider.overrideWithValue(repo),
      editLockProvider.overrideWith2(_HeldClaim.new),
    ]);
    await container.read(itineraryDetailProvider(_itinId).future);
    notifier = container.read(itineraryDetailProvider(_itinId).notifier);
  });

  tearDown(() => container.dispose());

  test('Given nothing is running, Then writesSettled answers at once', () async {
    expect(notifier.hasWritesInFlight, isFalse);
    expect(await notifier.writesSettled(), isTrue);
  });

  test(
      'Given a write, Then it is in flight until it and its refresh are done, '
      'and the claim reached the repository through the wrapper', () async {
    repo.refreshGate = Completer<void>();
    bool? settled;
    final write = notifier.updateSegment('seg-1', const {});
    await _settle();
    unawaited(notifier.writesSettled().then((ok) => settled = ok));

    expect(notifier.hasWritesInFlight, isTrue);
    expect(repo.lockTokens, ['lock-token']);

    repo.writes.single.complete();
    await _settle();
    // The write landed but the refresh has not: still in flight.
    expect(notifier.hasWritesInFlight, isTrue);
    expect(settled, isNull);

    repo.refreshGate!.complete();
    await write;
    await _settle();
    expect(notifier.hasWritesInFlight, isFalse);
    expect(settled, isTrue);
  });

  test(
      'Given a write that fails, Then writesSettled answers false and the '
      'error still reaches its caller', () async {
    bool? settled;
    final write = notifier.deleteSegment('seg-1');
    await _settle();
    unawaited(notifier.writesSettled().then((ok) => settled = ok));

    repo.writes.single.completeError(Exception('refused'));
    await expectLater(write, throwsException);
    await _settle();

    expect(notifier.hasWritesInFlight, isFalse);
    expect(settled, isFalse);
  });

  test(
      'Given two overlapping writes, Then it settles only once both are done, '
      'and false when either failed', () async {
    bool? settled;
    final first = notifier.updateSegment('seg-1', const {});
    final second = notifier.deleteSegment('seg-2');
    await _settle();
    unawaited(notifier.writesSettled().then((ok) => settled = ok));

    repo.writes[0].complete();
    await first;
    await _settle();
    expect(notifier.hasWritesInFlight, isTrue);
    expect(settled, isNull);

    repo.writes[1].completeError(Exception('refused'));
    await expectLater(second, throwsException);
    await _settle();
    expect(settled, isFalse);
  });

  test('Given a failure that has settled, Then the next write starts clean',
      () async {
    final failed = notifier.deleteSegment('seg-1');
    await _settle();
    repo.writes.single.completeError(Exception('refused'));
    await expectLater(failed, throwsException);

    bool? settled;
    final next = notifier.updateSegment('seg-1', const {});
    await _settle();
    unawaited(notifier.writesSettled().then((ok) => settled = ok));
    repo.writes.last.complete();
    await next;
    await _settle();

    expect(settled, isTrue);
  });
}
