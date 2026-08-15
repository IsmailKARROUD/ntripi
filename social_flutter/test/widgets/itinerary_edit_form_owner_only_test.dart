// test/widgets/itinerary_edit_form_owner_only_test.dart — The "Edit Itinerary"
// form is the trip's settings screen: cover, visibility, the editor list and
// delete are all owner-only server-side. A granted editor keeps the pencil
// (content editing) but must never reach this form — neither by the tune button
// nor by the route, which is directly addressable on web.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo({required this.canEdit}) : super(Dio());

  final bool canEdit;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 8, 15);
    return Itinerary(
      id: 'itin-1',
      userId: 'user-1',
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.onlyMe,
      createdAt: ts,
      updatedAt: ts,
      canEdit: canEdit,
    );
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

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required String viewerId,
  required bool canEdit,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_FakeRepo(canEdit: canEdit)),
      myProfileProvider.overrideWith(() => _FakeMyProfile(userId: viewerId)),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
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

    testWidgets('granted editor keeps the pencil but gets no tune button',
        (tester) async {
      await _pump(tester, const ItineraryDetailScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: true);

      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.byType(EditPencilButton), findsOneWidget);
    });
  });

  group('edit form route', () {
    testWidgets('owner reaching /edit gets the form', (tester) async {
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-1', canEdit: true);

      expect(find.text('Edit Itinerary'), findsOneWidget);
      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('granted editor reaching /edit directly is refused',
        (tester) async {
      await _pump(tester, const ItineraryFormScreen(itineraryId: 'itin-1'),
          viewerId: 'user-2', canEdit: true);

      expect(find.text("You don't have permission to modify this itinerary."),
          findsOneWidget);
      // The refusal replaces the whole form — no title field, no editor list,
      // no danger zone.
      expect(find.byType(Form), findsNothing);
    });
  });
}
