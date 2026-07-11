// test/widgets/itinerary_detail_cover_hint_test.dart — Owner tap on the
// placeholder cover pops the add-cover hint anchored to the Edit details
// button; viewers get nothing. Also guards the hero scrim's IgnorePointer —
// without it the scrim's BoxDecoration swallows the tap before it reaches
// the placeholder's GestureDetector.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/itinerary_cover_placeholder.dart';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo() : super(Dio());

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 7, 11);
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
    );
  }
}

class _FakeMyProfile extends MyProfileNotifier {
  final bool owner;
  _FakeMyProfile({required this.owner});

  @override
  Future<User> build() async => User(
        id: owner ? 'user-1' : 'user-2',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

Future<void> _pumpDetail(WidgetTester tester, {required bool owner}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_FakeRepo()),
      myProfileProvider.overrideWith(() => _FakeMyProfile(owner: owner)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ItineraryDetailScreen(itineraryId: 'itin-1'),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('owner tap on placeholder cover shows add-cover hint',
      (tester) async {
    await _pumpDetail(tester, owner: true);

    expect(find.byType(ItineraryCoverPlaceholder), findsOneWidget);
    await tester.tap(find.byType(ItineraryCoverPlaceholder),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Add a cover image'), findsOneWidget);
    expect(find.text('To add a cover image, tap this button at the top.'),
        findsOneWidget);
  });

  testWidgets('viewer tap on placeholder cover does nothing', (tester) async {
    await _pumpDetail(tester, owner: false);

    expect(find.byType(ItineraryCoverPlaceholder), findsOneWidget);
    await tester.tap(find.byType(ItineraryCoverPlaceholder),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Add a cover image'), findsNothing);
  });
}
