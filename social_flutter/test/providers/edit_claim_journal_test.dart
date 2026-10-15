// test/providers/edit_claim_journal_test.dart — a claim this device took and
// never released is handed back before the trip is next looked at.
//
// The claim token lives in memory and dies with the app. Without the journal, a
// claim the app was closed holding stayed on the server, and the next launch —
// holding no token for it — was told "you're editing this on another device"
// from the very device that left it, and refused a plain Edit until the claim
// was purged hours later.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/data/edit_claim_journal.dart';
import 'package:social_flutter/features/itineraries/data/edit_claim_store.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';

const _me = 'user-1';
const _itinId = 'itin-1';

String _key(String itineraryId) => '$kEditClaimKeyPrefix$itineraryId';

String _entry(String account, String token) =>
    jsonEncode({'account': account, 'token': token});

class _MemoryStore implements EditClaimStore {
  _MemoryStore([Map<String, String>? entries]) : entries = {...?entries};

  final Map<String, String> entries;

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<Map<String, String>> readAll() async => {...entries};

  @override
  Future<void> write(String key, String value) async {
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    entries.remove(key);
  }
}

/// Storage that refuses everything — a locked keychain, a full disk.
class _BrokenStore implements EditClaimStore {
  @override
  Future<String?> read(String key) => Future.error(StateError('locked'));

  @override
  Future<Map<String, String>> readAll() => Future.error(StateError('locked'));

  @override
  Future<void> write(String key, String value) =>
      Future.error(StateError('locked'));

  @override
  Future<void> delete(String key) => Future.error(StateError('locked'));
}

EditLock _mine() {
  final now = DateTime.now();
  return EditLock(
    holderId: _me,
    holderUsername: 'me',
    isYou: true,
    state: EditLockState.active,
    acquiredAt: now,
    lastHeartbeatAt: now,
    idleAt: now.add(const Duration(seconds: 90)),
    takeoverAvailableAt: now.add(const Duration(minutes: 5)),
  );
}

DioException _status(int code) {
  final options = RequestOptions(path: '/itineraries/$_itinId/lock');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: code),
  );
}

/// The server's lock, reduced to the one claim it can hold, plus every call in
/// the order it arrived.
class _LockServer extends ItineraryRepository {
  _LockServer({this.claimToken}) : super(Dio());

  /// The claim the server holds for [_me], by its token. Null: nobody's.
  String? claimToken;

  /// Thrown by the next releases, until cleared.
  Object? releaseError;

  final calls = <String>[];
  int _minted = 0;

  @override
  Future<void> releaseLock(String itineraryId, String? lockToken) async {
    calls.add('release $itineraryId $lockToken');
    if (releaseError case final error?) throw error;
    // Token-scoped, as the server is: a stale token ends nothing.
    if (lockToken == claimToken) claimToken = null;
  }

  @override
  Future<EditLockStatus> getLockStatus(String itineraryId) async {
    calls.add('status');
    return EditLockStatus(
      canEdit: true,
      lock: claimToken == null ? null : _mine(),
      heartbeatInterval: const Duration(seconds: 30),
      ttl: const Duration(minutes: 5),
    );
  }

  @override
  Future<EditLockClaim> acquireLock(
    String itineraryId, {
    bool takeover = false,
  }) async {
    calls.add(takeover ? 'takeover' : 'acquire');
    if (claimToken != null && !takeover) {
      throw ItineraryLockedException(_mine());
    }
    claimToken = 'tok-${++_minted}';
    return EditLockClaim(
      token: claimToken!,
      lock: _mine(),
      heartbeatInterval: const Duration(seconds: 30),
      ttl: const Duration(minutes: 5),
    );
  }
}

/// Sign-out's release step needs a Ref; a provider is the way to get one.
final _signOut = FutureProvider<void>(releaseAllEditClaims);

class _Harness {
  _Harness(this.server, this.store, this.journal, this.container);

  final _LockServer server;
  final EditClaimStore store;
  final EditClaimJournal journal;
  final ProviderContainer container;

  EditLockNotifier get notifier =>
      container.read(editLockProvider(_itinId).notifier);

  EditSession get session => container.read(editLockProvider(_itinId));
}

_Harness _harness({
  String? serverClaim,
  Map<String, String>? journalled,
  EditClaimStore? store,
}) {
  final server = _LockServer(claimToken: serverClaim);
  final backing = store ?? _MemoryStore(journalled);
  final journal = EditClaimJournal(backing, account: () async => _me);
  final container = ProviderContainer(overrides: [
    itineraryRepositoryProvider.overrideWithValue(server),
    editClaimJournalProvider.overrideWithValue(journal),
  ]);
  addTearDown(container.dispose);
  final h = _Harness(server, backing, journal, container);
  // A screen is on it, as in the app — no detach-grace release behind the test.
  h.notifier.attach();
  return h;
}

void main() {
  group('a claim the last run was closed holding', () {
    test(
        'Given the trip is looked at, Then the claim is handed back before the '
        'server is asked who is editing — and nobody is', () async {
      final h = _harness(
        serverClaim: 't-old',
        journalled: {_key(_itinId): _entry(_me, 't-old')},
      );

      final status = await h.notifier.peek();

      expect(h.server.calls, ['release $_itinId t-old', 'status']);
      expect(status!.lock, isNull);
      expect(h.session.lock, isNull);
      expect(await h.journal.leftover(_itinId), isNull);
    });

    test('Given Edit is tapped, Then a plain claim succeeds — no takeover',
        () async {
      final h = _harness(
        serverClaim: 't-old',
        journalled: {_key(_itinId): _entry(_me, 't-old')},
      );

      expect(await h.notifier.acquire(), isTrue);

      expect(h.server.calls, ['release $_itinId t-old', 'acquire']);
      expect(h.session.token, 'tok-1');
      // Journalled in its place, so it is handed back if this run is closed too.
      expect(await h.journal.leftover(_itinId), 'tok-1');
    });

    test(
        'Given the last run belonged to another account, Then its entry is '
        'dropped and never sent', () async {
      final h = _harness(
        journalled: {_key(_itinId): _entry('user-9', 't-theirs')},
      );

      await h.notifier.peek();

      expect(h.server.calls, ['status']);
      expect((h.store as _MemoryStore).entries, isEmpty);
    });

    for (final code in [403, 404]) {
      test(
          'Given the release answers $code, Then the entry is forgotten, not '
          'retried', () async {
        final h = _harness(
          serverClaim: 't-old',
          journalled: {_key(_itinId): _entry(_me, 't-old')},
        );
        h.server.releaseError = _status(code);

        await h.notifier.peek();
        await h.notifier.peek();

        expect(h.server.calls, ['release $_itinId t-old', 'status', 'status']);
        expect(await h.journal.leftover(_itinId), isNull);
      });
    }
  });

  group("this run's own claim", () {
    test('Given it is held, Then a look never hands it back', () async {
      final h = _harness();
      await h.notifier.acquire();

      await h.notifier.peek();

      expect(h.server.calls, ['acquire', 'status']);
      expect(h.session.holdsClaim, isTrue);
      expect(await h.journal.leftover(_itinId, live: 'tok-1'), isNull);
    });

    test(
        'Given its release could not land, Then the next look hands it back',
        () async {
      final h = _harness();
      await h.notifier.acquire();
      h.server.releaseError = DioException(
        requestOptions: RequestOptions(path: '/itineraries/$_itinId/lock'),
        type: DioExceptionType.connectionError,
      );

      await h.notifier.release();
      expect(await h.journal.leftover(_itinId), 'tok-1');

      h.server.releaseError = null;
      final status = await h.notifier.peek();

      expect(h.server.calls, [
        'acquire',
        'release $_itinId tok-1',
        'release $_itinId tok-1',
        'status',
      ]);
      expect(status!.lock, isNull);
      expect(await h.journal.leftover(_itinId), isNull);
    });

    test('Given it was released, Then nothing is left to hand back', () async {
      final h = _harness();
      await h.notifier.acquire();

      await h.notifier.release();
      await h.notifier.peek();

      expect(h.server.calls,
          ['acquire', 'release $_itinId tok-1', 'status']);
      expect(await h.journal.leftover(_itinId), isNull);
    });

    test('Given it was lost to a takeover, Then its dead token is forgotten',
        () async {
      final h = _harness();
      await h.notifier.acquire();

      h.notifier.markLost(null);

      expect(await h.journal.leftover(_itinId), isNull);
    });
  });

  group('the journal', () {
    test(
        'Given an old release lands after the trip was claimed again, Then the '
        "new claim's entry stays", () async {
      final journal =
          EditClaimJournal(_MemoryStore(), account: () async => _me);
      await journal.record(_itinId, 't1');
      await journal.record(_itinId, 't2');

      await journal.forget(_itinId, 't1');

      expect(await journal.leftover(_itinId), 't2');
    });

    test(
        'Given storage refuses everything, Then looking and claiming work as '
        'they did before the journal', () async {
      final h = _harness(store: _BrokenStore());

      final status = await h.notifier.peek();
      final claimed = await h.notifier.acquire();

      expect(status, isNotNull);
      expect(claimed, isTrue);
      expect(h.server.calls, ['status', 'acquire']);
    });
  });

  test(
      'Given sign-out, Then every claim this account left is handed back and '
      'the journal is emptied', () async {
    final h = _harness(journalled: {
      _key('itin-1'): _entry(_me, 't-a'),
      _key('itin-2'): _entry(_me, 't-b'),
      _key('itin-3'): _entry('user-9', 't-c'),
    });

    await h.container.read(_signOut.future);

    expect(h.server.calls, unorderedEquals(['release itin-1 t-a', 'release itin-2 t-b']));
    expect((h.store as _MemoryStore).entries, isEmpty);
  });
}
