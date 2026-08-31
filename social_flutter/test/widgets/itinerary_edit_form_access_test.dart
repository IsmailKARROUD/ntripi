// test/widgets/itinerary_edit_form_access_test.dart — The "Edit Itinerary" form
// is not one permission. The server accepts title, currency and the recommended
// period from a granted editor, but cover, visibility, the editor list and
// delete are owner-only — so the form opens for both and hides the owner-only
// controls, rather than refusing the whole screen and taking the three fields
// an editor may already change away with it.
//
// The payload test is the load-bearing one: `visibility` must be ABSENT for an
// editor (the server rejects the key, not the value), and `currency` must carry
// the trip's real currency rather than the EUR fallback.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/recommended_period_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

// MAD, not EUR: seeding the picker from the server value used to be a no-op
// (a List<Currency>.contains(String)), so every save rewrote the currency to
// the EUR fallback. A EUR fixture could not tell the two apart.
const _kCurrency = 'MAD';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo({required this.canEdit, this.gate, this.updateGate, this.period})
      : super(Dio());

  final bool canEdit;

  /// When set, getItinerary parks on it — the window in which the form holds
  /// nothing but its defaults and must not claim the trip has no best time.
  final Completer<void>? gate;

  /// When set, updateItinerary parks on it — the window the detail screen has
  /// to account for after the picker pops and before the PATCH answers.
  final Completer<void>? updateGate;

  final RecommendedPeriod? period;

  /// The body of the last PATCH, or null if none went out.
  Map<String, dynamic>? lastUpdate;

  Itinerary _itinerary() {
    final ts = DateTime.utc(2026, 8, 15);
    return Itinerary(
      id: 'itin-1',
      userId: 'user-1',
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: _kCurrency,
      visibility: ItineraryVisibility.onlyMe,
      createdAt: ts,
      updatedAt: ts,
      canEdit: canEdit,
      recommendedPeriod: period,
    );
  }

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    if (gate != null) await gate!.future;
    return _itinerary();
  }

  @override
  Future<Itinerary> updateItinerary(
    String id,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) async {
    lastUpdate = data;
    if (updateGate != null) await updateGate!.future;
    return _itinerary();
  }
}

/// Grants the claim without a round trip and, more importantly, without the
/// heartbeat Timer the real one starts — a pending timer fails the test at
/// teardown, and none of this is what the assertions are about.
class _FakeEditLock extends EditLockNotifier {
  _FakeEditLock(super.arg);

  @override
  EditSession build() => const EditSession();

  @override
  Future<bool> acquire({bool takeover = false}) async {
    state = const EditSession(token: 'lock-token');
    return true;
  }

  @override
  Future<EditLockStatus?> peek() async => null;

  @override
  Future<void> release() async => state = const EditSession();
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

/// Pumps [home] as a PUSHED route, not as `home:`. The form pops itself after a
/// successful save (and after self-removal), which is a go_router call needing
/// both a GoRouter in context and something underneath to pop back to.
Future<_FakeRepo> _pump(
  WidgetTester tester,
  Widget home, {
  required String viewerId,
  required bool canEdit,
  Completer<void>? gate,
  Completer<void>? updateGate,
  RecommendedPeriod? period,
}) async {
  // Tall enough that the whole form is laid out at once. Without this a
  // ListView simply never builds its off-screen children, so every findsNothing
  // below would pass for the wrong reason — including on a form that still
  // offered the editor a delete button.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _FakeRepo(
      canEdit: canEdit, gate: gate, updateGate: updateGate, period: period);
  final router = GoRouter(
    routes: [
      GoRoute(
          path: '/', builder: (_, _) => const Scaffold(body: Text('beneath'))),
      GoRoute(path: '/target', builder: (_, _) => home),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(repo),
      myProfileProvider.overrideWith(() => _FakeMyProfile(userId: viewerId)),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      editLockProvider.overrideWith2((id) => _FakeEditLock(id)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  router.push('/target');
  if (gate == null) {
    await tester.pumpAndSettle();
  } else {
    // pumpAndSettle would never return: the loading row mounts a repeating
    // NTripiRingLoader, which schedules a frame forever. Two fixed pumps are
    // enough to start and finish the push transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return repo;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('detail hero chrome', () {
    testWidgets('owner gets the settings (tune) button', (tester) async {
      await _pump(tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true);

      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byType(EditPencilButton), findsOneWidget);
    });

    testWidgets('granted editor gets the tune button too', (tester) async {
      await _pump(tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: true);

      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byType(EditPencilButton), findsOneWidget);
    });

    testWidgets('a plain viewer gets neither', (tester) async {
      await _pump(tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: false);

      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.byType(EditPencilButton), findsNothing);
    });
  });

  group('edit form route', () {
    testWidgets('owner gets the whole form', (tester) async {
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true);

      expect(find.text('Edit Itinerary'), findsOneWidget);
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(CoverImageField), findsOneWidget);
      expect(find.text('WHO CAN SEE THIS?'), findsOneWidget);
      expect(find.text('Who can edit'), findsOneWidget);
      expect(find.text('DELETE ITINERARY'), findsOneWidget);
      // The owner's way out is deleting the trip, not resigning from it.
      expect(find.text('REMOVE ME AS EDITOR'), findsNothing);
    });

    testWidgets('granted editor gets the reduced form', (tester) async {
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: true);

      expect(find.byType(Form), findsOneWidget);
      // What the server already accepts from an editor.
      expect(find.text('CURRENCY'), findsOneWidget);
      expect(find.text('BEST TIME TO VISIT'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget); // the title
      // What it does not — hidden rather than offered and left to 403.
      expect(find.byType(CoverImageField), findsNothing);
      expect(find.text('WHO CAN SEE THIS?'), findsNothing);
      expect(find.text('Who can edit'), findsNothing);
      expect(find.text('DELETE ITINERARY'), findsNothing);
      // …and the way out that IS theirs, in the same danger-zone chrome the
      // owner's delete row wears.
      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('REMOVE ME AS EDITOR'), findsOneWidget);
    });

    testWidgets('someone who can neither own nor edit is refused',
        (tester) async {
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: false);

      expect(find.text("You don't have permission to modify this itinerary."),
          findsOneWidget);
      // The refusal replaces the whole form.
      expect(find.byType(Form), findsNothing);
    });
  });

  group('PATCH payload', () {
    testWidgets('editor sends no visibility key and keeps the currency',
        (tester) async {
      final repo = await _pump(
          tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: true);

      await tester.enterText(find.byType(TextFormField), 'Trip renamed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final body = repo.lastUpdate;
      expect(body, isNotNull);
      expect(body!['title'], 'Trip renamed');
      // The server refuses the KEY for a non-owner, so an explicit null 403s
      // exactly as a real value would.
      expect(body.containsKey('visibility'), isFalse);
      // Not the EUR fallback: a title-only edit must not rewrite the currency.
      expect(body['currency'], _kCurrency);
    });

    testWidgets('owner still sends visibility', (tester) async {
      final repo = await _pump(
          tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true);

      await tester.enterText(find.byType(TextFormField), 'Trip renamed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final body = repo.lastUpdate;
      expect(body, isNotNull);
      expect(body!['visibility'], 'only_me');
      expect(body['currency'], _kCurrency);
    });
  });

  // A note-only period: shortLabel falls through to the note, so the expected
  // string is the same in all six locales — no date formatting to pin down.
  const period = RecommendedPeriod(note: 'Shoulder season');

  group('best time to visit, before the detail arrives', () {
    testWidgets('shows a loader instead of claiming "Not set"', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true, gate: gate, period: period);

      final row = find
          .ancestor(
              of: find.text('BEST TIME TO VISIT'), matching: find.byType(InkWell))
          .first;
      expect(find.descendant(of: row, matching: find.byType(NTripiRingLoader)),
          findsOneWidget);
      // The whole point: the form must not report a period the trip has.
      expect(find.text('Not set'), findsNothing);
    });

    testWidgets('refuses the tap so an empty picker cannot clear it',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true, gate: gate, period: period);

      await tester.tap(find.text('BEST TIME TO VISIT'));
      // First pump inserts the pushed route, second runs its transition out —
      // one combined pump finds nothing whether or not the tap was refused.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // toPayload() always emits all three keys, so a Done on an empty picker
      // would reach the server as three explicit nulls.
      expect(find.byType(RecommendedPeriodScreen), findsNothing);
    });

    testWidgets('swaps in the real value once it lands', (tester) async {
      final gate = Completer<void>();
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true, gate: gate, period: period);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(NTripiRingLoader), findsNothing);
      expect(find.text('Shoulder season'), findsOneWidget);
    });
  });
  group('best time to visit, while the save is in flight', () {
    // The picker pops on Done and the PATCH runs back on the detail screen, so
    // this window is the one the user actually sees: without a cue the screen
    // looks idle and the value changes on its own some time later.
    Future<void> openPickerAndTapDone(WidgetTester tester) async {
      await tester.tap(find.byType(EditPencilButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Best time to visit'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RecommendedPeriodScreen), findsOneWidget);
      await tester.tap(find.text('Done'));
      // No settle: the row that comes back is spinning, and a repeating
      // animation never settles.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the row spins until the PATCH answers', (tester) async {
      final updateGate = Completer<void>();
      addTearDown(() {
        if (!updateGate.isCompleted) updateGate.complete();
      });
      final repo = await _pump(
          tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true, updateGate: updateGate);

      await openPickerAndTapDone(tester);

      expect(repo.lastUpdate, isNotNull, reason: 'the PATCH should be in flight');
      final row = find.ancestor(
          of: find.text('Best time to visit'), matching: find.byType(InkWell));
      expect(find.descendant(of: row, matching: find.byType(NTripiRingLoader)),
          findsOneWidget);
      // Scoped to the row: the description row carries its own pencil, and the
      // loader only ever stands in for this one.
      expect(find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
          findsNothing);
    });

    testWidgets('the spinner clears once it lands', (tester) async {
      final updateGate = Completer<void>();
      await _pump(tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true, updateGate: updateGate);

      await openPickerAndTapDone(tester);
      updateGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(NTripiRingLoader), findsNothing);
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('Best time to visit'),
                  matching: find.byType(InkWell)),
              matching: find.byIcon(Icons.edit_outlined)),
          findsOneWidget);
    });

    testWidgets('a failed save clears it too, and says why', (tester) async {
      // finally, not the success path: a spinner left running behind the
      // snackbar would strand the row forever.
      final updateGate = Completer<void>();
      await _pump(tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true, updateGate: updateGate);

      await openPickerAndTapDone(tester);
      updateGate.completeError(ItineraryStaleException());
      await tester.pumpAndSettle();

      expect(find.byType(NTripiRingLoader), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
