// test/widgets/edit_lock_relaunch_test.dart — reopening a trip the app was
// closed editing.
//
// Reported 2026-10-15: enter Edit mode, close the app, reopen the same trip, and
// the banner said "You're editing this on another device". The claim token
// lived in memory, so the relaunched app could not recognise the claim it had
// left on the server; the server's `is_you` was all it had to go on. With the
// claim journalled, the first look at the trip hands it back, and the trip opens
// as it would after leaving edit mode properly.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/edit_claim_journal.dart';
import 'package:ntripi/features/itineraries/data/edit_claim_store.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/edit_lock.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/edit_lock_banner.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/translation/domain/translation.dart';
import 'package:ntripi/features/translation/providers/translation_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

const _owner = 'user-1';
const _itinId = 'itin-1';
const _youElsewhere = "You're editing this on another device";

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

EditLock _mine() {
  final now = DateTime.now();
  return EditLock(
    holderId: _owner,
    holderUsername: 'me',
    isYou: true,
    state: EditLockState.active,
    acquiredAt: now.subtract(const Duration(minutes: 1)),
    lastHeartbeatAt: now,
    idleAt: now.add(const Duration(seconds: 90)),
    takeoverAvailableAt: now.add(const Duration(minutes: 5)),
  );
}

/// The owner's trip, and a lock that holds at most one claim of theirs — keyed
/// by token, the way the server's release is.
class _Server extends ItineraryRepository {
  _Server({this.claimToken}) : super(Dio());

  String? claimToken;
  final calls = <String>[];

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 10, 15);
    return Itinerary(
      id: _itinId,
      userId: _owner,
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.onlyMe,
      createdAt: ts,
      updatedAt: ts,
      tracks: [
        Track(
          id: 'track-1',
          itineraryId: _itinId,
          rank: 'a',
          stops: [
            Stop(
              id: 'stop-1',
              itineraryId: _itinId,
              trackId: 'track-1',
              rank: 'a',
              type: StopType.origin,
              placeName: 'Old Port',
              createdAt: ts,
            ),
          ],
        ),
      ],
    );
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
  Future<void> releaseLock(String itineraryId, String? lockToken) async {
    calls.add('release $lockToken');
    if (lockToken == claimToken) claimToken = null;
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
    claimToken = 'tok-new';
    return EditLockClaim(
      token: 'tok-new',
      lock: _mine(),
      heartbeatInterval: const Duration(seconds: 30),
      ttl: const Duration(minutes: 5),
    );
  }
}

class _FakeMyProfile extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: _owner,
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

Future<void> _pump(WidgetTester tester, _Server server, EditClaimStore store) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/itineraries/$_itinId',
    routes: [
      GoRoute(
        path: '/itineraries/:id',
        builder: (_, s) =>
            ItineraryDetailScreen(itineraryId: s.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(server),
      editClaimJournalProvider.overrideWithValue(
          EditClaimJournal(store, account: () async => _owner)),
      myProfileProvider.overrideWith(_FakeMyProfile.new),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      translationConfigProvider
          .overrideWith((ref) async => TranslationConfig.disabled),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // The one-time long-press tip would sit over the trip page in read mode.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets(
      'a trip the app was closed editing opens in read mode, with no "another '
      'device" banner, and Edit enters edit mode without asking',
      (tester) async {
    final server = _Server(claimToken: 't-old');
    final store = _MemoryStore({
      '$kEditClaimKeyPrefix$_itinId':
          jsonEncode({'account': _owner, 'token': 't-old'}),
    });

    await _pump(tester, server, store);

    // Handed back before the server was asked who is editing.
    expect(server.calls.take(2), ['release t-old', 'status']);
    expect(find.byType(EditLockBanner), findsNothing);
    expect(find.text(_youElsewhere), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.tap(find.byType(EditPencilButton));
    await tester.pumpAndSettle();

    expect(find.text('Continue here'), findsNothing);
    expect(server.calls.last, 'acquire');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets(
      'a claim this device never held still reads as another device — that is '
      'the case the banner is for', (tester) async {
    final server = _Server(claimToken: 't-tablet');

    await _pump(tester, server, _MemoryStore());

    expect(server.calls, isNot(contains(startsWith('release'))));
    expect(find.byType(EditLockBanner), findsOneWidget);
    expect(find.text(_youElsewhere), findsOneWidget);
  });
}
