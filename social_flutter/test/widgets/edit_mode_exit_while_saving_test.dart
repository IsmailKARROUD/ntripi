// test/widgets/edit_mode_exit_while_saving_test.dart — ✓ and Back never hand
// the edit claim back under a running save.
//
// Leaving edit mode releases the claim, and a write still on its way carries
// it: released first, the server refused the write after the card showing its
// spinner had gone, and the change was lost without a word. So while a save
// runs, ✓ and Back put the page under SavingOverlay with a message and leave
// edit mode once the save lands — or stay, under that save's own error.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

const _owner = 'user-1';
const _waitMessage =
    "Saving your changes… You'll leave edit mode as soon as they're saved.";
const _stayedMessage = "Your change wasn't saved, so you're still in edit mode.";

/// Serves a two-stop trip joined by one metro leg, and holds every segment
/// save open until the test answers it.
class _GatedRepo extends ItineraryRepository {
  _GatedRepo() : super(Dio());

  Completer<void>? save;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 10, 10);
    Stop stop(String id, String trackId, StopType type, String name) => Stop(
          id: id,
          itineraryId: 'itin-1',
          trackId: trackId,
          rank: 'a',
          type: type,
          placeName: name,
          createdAt: ts,
        );
    return Itinerary(
      id: 'itin-1',
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
          itineraryId: 'itin-1',
          rank: 'a',
          stops: [stop('stop-1', 'track-1', StopType.origin, 'Old Port')],
        ),
        Track(
          id: 'track-2',
          itineraryId: 'itin-1',
          rank: 'b',
          stops: [stop('stop-2', 'track-2', StopType.arrival, 'Museum')],
        ),
      ],
      segments: [
        TransitSegment(
          id: 'seg-1',
          itineraryId: 'itin-1',
          fromStopId: 'stop-1',
          toStopId: 'stop-2',
          totalDurationMin: 12,
          totalCost: 0.0,
          createdAt: ts,
          legs: [
            TransportLeg(
              id: 'leg-1',
              segmentId: 'seg-1',
              position: 1,
              mode: TransportMode.metro,
              line: 'M1',
              durationMin: 12,
              notes: 'Board at the front.',
              createdAt: ts,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<TransitSegment> updateSegment(
    String itineraryId,
    String segmentId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) async {
    final gate = save = Completer<void>();
    await gate.future;
    return TransitSegment(
      id: segmentId,
      itineraryId: itineraryId,
      fromStopId: 'stop-1',
      toStopId: 'stop-2',
      totalDurationMin: 12,
      totalCost: 0.0,
      createdAt: DateTime.utc(2026, 10, 10),
    );
  }
}

/// This device holds the claim; counts how often it is handed back.
class _HeldClaim extends EditLockNotifier {
  _HeldClaim(super.arg);

  int releases = 0;

  @override
  EditSession build() {
    // super.build registers the real teardown, which cancels the detach grace
    // timer when the container goes.
    super.build();
    return const EditSession(token: 'lock-token');
  }

  @override
  Future<EditLockStatus?> peek() async => null;

  @override
  Future<void> release() async {
    releases++;
    state = const EditSession();
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

class _Harness {
  _Harness(this.repo, this._claim);

  final _GatedRepo repo;
  final _HeldClaim? Function() _claim;

  _HeldClaim get claim => _claim()!;
}

Future<_Harness> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _GatedRepo();
  _HeldClaim? claim;
  final router = GoRouter(
    initialLocation: '/itineraries/itin-1',
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
      itineraryRepositoryProvider.overrideWithValue(repo),
      myProfileProvider.overrideWith(_FakeMyProfile.new),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      translationConfigProvider
          .overrideWith((ref) async => TranslationConfig.disabled),
      editLockProvider.overrideWith2((id) => claim = _HeldClaim(id)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return _Harness(repo, () => claim);
}

/// Opens the leg from its row and saves it unchanged — the save is held open.
Future<void> _startLegSave(WidgetTester tester) async {
  await tester.tap(find.text('Metro'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Update Transit'));
  await tester.tap(find.text('Update Transit'));
  await tester.pump();
}

Finder get _done => find.byIcon(Icons.check_rounded);

bool _overlayShowing(WidgetTester tester) =>
    tester.widget<SavingOverlay>(find.byType(SavingOverlay)).saving;

void main() {
  // The one-time long-press tip would sit over the page.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets('Given nothing is saving, ✓ leaves edit mode at once',
      (tester) async {
    final h = await _pump(tester);

    await tester.tap(_done);
    await tester.pumpAndSettle();

    expect(_done, findsNothing);
    expect(find.byType(EditPencilButton), findsOneWidget);
    expect(h.claim.releases, 1);
    expect(find.text(_waitMessage), findsNothing);
  });

  testWidgets(
      'Given a leg is saving, ✓ keeps the claim and says so, then leaves edit '
      'mode once the save lands', (tester) async {
    final h = await _pump(tester);
    await _startLegSave(tester);
    expect(h.repo.save, isNotNull);

    await tester.tap(_done);
    await tester.pump();

    expect(_overlayShowing(tester), isTrue);
    expect(find.text(_waitMessage), findsOneWidget);
    expect(h.claim.releases, 0);
    // Still editing: no new edit can start, and ✓ again only waits.
    await tester.tap(_done, warnIfMissed: false);
    await tester.pump();
    expect(h.claim.releases, 0);

    h.repo.save!.complete();
    await tester.pumpAndSettle();

    expect(_overlayShowing(tester), isFalse);
    expect(find.text(_waitMessage), findsNothing);
    expect(_done, findsNothing);
    expect(h.claim.releases, 1);
  });

  testWidgets(
      'Given the save fails, the page stays in edit mode with the claim: the '
      "save's own error, then why it is still editing", (tester) async {
    final h = await _pump(tester);
    await _startLegSave(tester);

    await tester.tap(_done);
    await tester.pump();
    expect(find.text(_waitMessage), findsOneWidget);

    h.repo.save!.completeError(Exception('refused'));
    await tester.pumpAndSettle();

    expect(_overlayShowing(tester), isFalse);
    expect(_done, findsOneWidget);
    expect(h.claim.releases, 0);
    // First the error the leg's own editor shows…
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_stayedMessage), findsNothing);

    // …then, once it has had its turn, why the page did not leave.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(_stayedMessage), findsOneWidget);
  });

  testWidgets('Given a leg is saving, Back waits for it the same way',
      (tester) async {
    final h = await _pump(tester);
    await _startLegSave(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text(_waitMessage), findsOneWidget);
    expect(h.claim.releases, 0);

    h.repo.save!.complete();
    await tester.pumpAndSettle();

    expect(_done, findsNothing);
    expect(h.claim.releases, 1);
  });
}
