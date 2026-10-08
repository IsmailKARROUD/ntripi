// test/widgets/stop_detail_edit_lock_test.dart — Editing from a stop's own page
// is the trip's edit mode, not a side door around it.
//
// The pencil stays for anyone who may edit. Tapping it claims the trip and KEEPS
// the claim, so the trip page underneath is in edit mode when the user goes
// back. When somebody else holds the trip, a pop-up names them and offers the
// takeover the trip page's banner would — owners always, your own other device
// always, an editor only once the server calls the claim takeable — and taking
// over opens nothing: the user taps Edit afterwards.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
import 'package:social_flutter/features/translation/presentation/translatable_text.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

const _owner = 'user-1';
const _tripPath = '/itineraries/itin-1';
const _stopPath = '/itineraries/itin-1/stops/stop-1';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo({required this.canEdit}) : super(Dio());

  final bool canEdit;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 10, 8);
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
      canEdit: canEdit,
      tracks: [
        Track(
          id: 'track-1',
          itineraryId: 'itin-1',
          rank: 'a',
          stops: [
            Stop(
              id: 'stop-1',
              itineraryId: 'itin-1',
              trackId: 'track-1',
              rank: 'a',
              type: StopType.origin,
              placeName: 'Old Port',
              notes: 'Arrive early.',
              annotations: [
                Annotation(
                  id: 'anno-1',
                  stopId: 'stop-1',
                  type: AnnotationType.advice,
                  content: 'Bring cash',
                  createdAt: ts,
                  updatedAt: ts,
                ),
              ],
              createdAt: ts,
            ),
          ],
        ),
      ],
    );
  }
}

/// A claim without the network or the heartbeat Timer. [heldBy] is somebody
/// else's claim: a plain acquire is refused with it, a takeover wins.
class _FakeEditLock extends EditLockNotifier {
  _FakeEditLock(super.arg, {required this.initial, this.heldBy});

  final EditSession initial;
  final EditLock? heldBy;

  int acquires = 0;
  int takeovers = 0;
  int releases = 0;

  @override
  EditSession build() {
    // super.build registers the real teardown, which cancels the detach grace
    // timer when the container goes.
    super.build();
    return initial;
  }

  @override
  Future<bool> acquire({bool takeover = false}) async {
    if (takeover) {
      takeovers++;
    } else {
      acquires++;
      if (heldBy != null) {
        state = EditSession(lock: heldBy, problem: EditSessionProblem.locked);
        return false;
      }
    }
    state = const EditSession(token: 'lock-token');
    return true;
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
  _FakeMyProfile({required this.userId});

  final String userId;

  @override
  Future<User> build() async => User(
        id: userId,
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

EditLock _lock({
  required EditLockState state,
  bool isYou = false,
  Duration takeoverIn = const Duration(minutes: 4),
}) {
  final now = DateTime.now();
  return EditLock(
    holderId: isYou ? _owner : 'user-3',
    holderUsername: 'ana',
    holderDisplayName: 'Ana',
    isYou: isYou,
    state: state,
    acquiredAt: now.subtract(const Duration(minutes: 1)),
    lastHeartbeatAt: now,
    idleAt: now.add(const Duration(minutes: 1)),
    takeoverAvailableAt: now.add(takeoverIn),
  );
}

class _Harness {
  _Harness(this.router, this._lock);

  final GoRouter router;
  final _FakeEditLock? Function() _lock;

  _FakeEditLock get lock => _lock()!;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String viewerId = _owner,
  bool canEdit = false,
  EditSession initial = const EditSession(),
  EditLock? heldBy,
  String start = _stopPath,
}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _FakeEditLock? lock;
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/itineraries/:id',
        builder: (_, s) =>
            ItineraryDetailScreen(itineraryId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/itineraries/:id/stops/:stopId',
        builder: (_, s) => StopDetailScreen(
          itineraryId: s.pathParameters['id']!,
          stopId: s.pathParameters['stopId']!,
        ),
      ),
      // The form itself is not what this file is about — only that it opened.
      GoRoute(
        path: '/itineraries/:id/stops/:stopId/edit',
        builder: (_, _) => const Scaffold(body: Text('stop form')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_FakeRepo(canEdit: canEdit)),
      myProfileProvider.overrideWith(() => _FakeMyProfile(userId: viewerId)),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      translationConfigProvider
          .overrideWith((ref) async => TranslationConfig.disabled),
      editLockProvider.overrideWith2(
          (id) => lock = _FakeEditLock(id, initial: initial, heldBy: heldBy)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return _Harness(router, () => lock);
}

Future<void> _tapPencil(WidgetTester tester) async {
  await tester.tap(find.byType(EditPencilButton));
  await tester.pumpAndSettle();
}

void main() {
  // The one-time long-press tip would sit over the trip page in read mode.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  group('who gets the pencil', () {
    testWidgets('the owner, in read mode, and never the flag', (tester) async {
      await _pump(tester);

      expect(find.byType(EditPencilButton), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
    });

    testWidgets('a granted editor too', (tester) async {
      await _pump(tester, viewerId: 'user-2', canEdit: true);

      expect(find.byType(EditPencilButton), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
    });

    testWidgets('a plain viewer gets the flag instead', (tester) async {
      await _pump(tester, viewerId: 'user-2');

      expect(find.byType(EditPencilButton), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    });
  });

  group('an unlocked trip', () {
    testWidgets('Edit claims it, opens the form, and keeps the claim',
        (tester) async {
      final h = await _pump(tester);

      await _tapPencil(tester);

      expect(h.lock.acquires, 1);
      expect(find.text('stop form'), findsOneWidget);

      h.router.pop();
      await tester.pumpAndSettle();

      // Still editing: the claim is the trip's edit mode now, not a loan.
      expect(find.byType(StopDetailScreen), findsOneWidget);
      expect(h.lock.releases, 0);
      expect(h.lock.state.holdsClaim, isTrue);
    });

    testWidgets('the trip page underneath follows into edit mode',
        (tester) async {
      final h = await _pump(tester, start: _tripPath);
      // Read mode: the hero offers the pencil, not the ✓.
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.tap(find.text('Old Port'));
      await tester.pumpAndSettle();
      expect(find.byType(StopDetailScreen), findsOneWidget);

      await _tapPencil(tester);
      expect(find.text('stop form'), findsOneWidget);

      h.router.pop(); // the form
      await tester.pumpAndSettle();
      h.router.pop(); // the stop page
      await tester.pumpAndSettle();

      expect(find.byType(StopDetailScreen), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('a trip somebody else holds', () {
    testWidgets('the owner is offered the takeover, and Edit comes after',
        (tester) async {
      final h = await _pump(tester,
          heldBy: _lock(state: EditLockState.active));

      await _tapPencil(tester);

      expect(find.text('Ana is editing'), findsOneWidget);
      expect(find.text('You own this trip — you can take over at any time.'),
          findsOneWidget);
      expect(find.text('stop form'), findsNothing);

      await tester.tap(find.text('Take over'));
      await tester.pumpAndSettle();

      // Taking over only claims the trip; nothing opens on its own.
      expect(h.lock.takeovers, 1);
      expect(find.text('stop form'), findsNothing);
      expect(find.byType(StopDetailScreen), findsOneWidget);

      await _tapPencil(tester);

      expect(find.text('stop form'), findsOneWidget);
      // The second tap found the claim held and did not ask again.
      expect(h.lock.acquires, 1);
    });

    testWidgets('an editor facing an active claim is only told when',
        (tester) async {
      final h = await _pump(tester,
          viewerId: 'user-2',
          canEdit: true,
          heldBy: _lock(state: EditLockState.active));

      await _tapPencil(tester);

      expect(find.text('Ana is editing'), findsOneWidget);
      expect(find.textContaining('You can take over in'), findsOneWidget);
      expect(find.text('Take over'), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Ana is editing'), findsNothing);
      expect(h.lock.takeovers, 0);
      expect(find.text('stop form'), findsNothing);
    });

    testWidgets('an editor is offered it once the server says takeable',
        (tester) async {
      final h = await _pump(tester,
          viewerId: 'user-2',
          canEdit: true,
          heldBy: _lock(
              state: EditLockState.takeable, takeoverIn: Duration.zero));

      await _tapPencil(tester);

      expect(find.text('Ana is editing · away'), findsOneWidget);
      expect(find.text('You can take over now'), findsOneWidget);

      await tester.tap(find.text('Take over'));
      await tester.pumpAndSettle();

      expect(h.lock.takeovers, 1);
    });

    testWidgets('your own other device offers Continue here', (tester) async {
      final h = await _pump(tester,
          heldBy: _lock(state: EditLockState.active, isYou: true));

      await _tapPencil(tester);

      expect(find.text("You're editing this on another device"),
          findsOneWidget);
      await tester.tap(find.text('Continue here'));
      await tester.pumpAndSettle();

      expect(h.lock.takeovers, 1);
    });

    testWidgets('a long-press asks the same way', (tester) async {
      final h = await _pump(tester,
          heldBy: _lock(state: EditLockState.active));

      await tester.longPress(find.text('Bring cash'));
      await tester.pumpAndSettle();

      expect(h.lock.acquires, 1);
      expect(find.text('Ana is editing'), findsOneWidget);
      expect(find.text('Take over'), findsOneWidget);
    });
  });

  // skipOffstage: false — translation is off here, so the toggle draws nothing
  // and its zero-height sliver reads as offstage. What is asserted is whether
  // the page builds it at all.
  group('translation follows the mode', () {
    testWidgets('offered in read mode', (tester) async {
      await _pump(tester);

      expect(find.byType(TranslationToggle, skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('withdrawn in edit mode — the editor reads the original',
        (tester) async {
      await _pump(tester, initial: const EditSession(token: 'lock-token'));

      expect(find.byType(TranslationToggle, skipOffstage: false),
          findsNothing);
    });
  });
}
