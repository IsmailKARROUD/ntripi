// test/providers/itinerary_writes_in_flight_test.dart — what leaving edit mode
// waits on.
//
// Every write that carries this device's edit claim runs through one wrapper in
// ItineraryDetailNotifier, which counts it until its answer is adopted.
// ✓ and Back wait on writesSettled(): handing the claim back under a running
// write made the server refuse it, after the card showing its spinner had gone.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/trip_edit_answer.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';

import '../support/held_claim.dart';

const _itinId = 'itin-1';

Itinerary _trip(DateTime ts) => Itinerary(
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

/// Holds every segment write open until the test answers it.
class _GatedRepo extends ItineraryRepository {
  _GatedRepo() : super(Dio());

  final writes = <Completer<void>>[];
  final lockTokens = <String?>[];
  int loads = 0;

  /// What every save answers with: the trip, a later stamp.
  final answered = _trip(DateTime.utc(2026, 10, 10, 0, 0, 5));

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    loads++;
    return _trip(DateTime.utc(2026, 10, 10));
  }

  Future<TripEditAnswer> _held(String? lockToken) async {
    lockTokens.add(lockToken);
    final gate = Completer<void>();
    writes.add(gate);
    await gate.future;
    return TripEditAnswer(answered);
  }

  @override
  Future<TripEditAnswer> updateSegment(
    String itineraryId,
    String segmentId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _held(lockToken);

  @override
  Future<TripEditAnswer> deleteSegment(
    String itineraryId,
    String segmentId, {
    required String etag,
    required String? lockToken,
  }) =>
      _held(lockToken);
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
      editLockProvider.overrideWith2(HeldClaim.new),
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
      'Given a write, Then it is in flight until its answer is adopted — no '
      'reload behind it — and the claim reached the repository through the '
      'wrapper', () async {
    bool? settled;
    final write = notifier.updateSegment('seg-1', const {});
    await _settle();
    unawaited(notifier.writesSettled().then((ok) => settled = ok));

    expect(notifier.hasWritesInFlight, isTrue);
    expect(settled, isNull);
    expect(repo.lockTokens, ['lock-token']);

    repo.writes.single.complete();
    await write;
    await _settle();
    expect(notifier.hasWritesInFlight, isFalse);
    expect(settled, isTrue);
    expect(container.read(itineraryDetailProvider(_itinId)).value,
        same(repo.answered));
    expect(repo.loads, 1);
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
