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
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/editor_access_row.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

// MAD, not EUR: seeding the picker from the server value used to be a no-op
// (a List<Currency>.contains(String)), so every save rewrote the currency to
// the EUR fallback. A EUR fixture could not tell the two apart.
const _kCurrency = 'MAD';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo({required this.canEdit}) : super(Dio());

  final bool canEdit;

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
    );
  }

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async =>
      _itinerary();

  @override
  Future<Itinerary> updateItinerary(
    String id,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) async {
    lastUpdate = data;
    return _itinerary();
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

/// Pumps [home] as a PUSHED route, not as `home:`. The form pops itself after a
/// successful save (and after self-removal), which is a go_router call needing
/// both a GoRouter in context and something underneath to pop back to.
Future<_FakeRepo> _pump(
  WidgetTester tester,
  Widget home, {
  required String viewerId,
  required bool canEdit,
}) async {
  // Tall enough that the whole form is laid out at once. Without this a
  // ListView simply never builds its off-screen children, so every findsNothing
  // below would pass for the wrong reason — including on a form that still
  // offered the editor a delete button.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _FakeRepo(canEdit: canEdit);
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
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  router.push('/target');
  await tester.pumpAndSettle();
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
      expect(find.byType(EditorAccessRow), findsNothing);
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
      expect(find.text('DANGER ZONE'), findsNothing);
      // …and the way out that IS theirs.
      expect(find.byType(EditorAccessRow), findsOneWidget);
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
}
