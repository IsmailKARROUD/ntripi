// The stop form's notes rise above the keyboard.
//
// Regression: the form set `resizeToAvoidBottomInset: false` and lives on the
// root navigator (/itineraries/:id/stops/new and …/edit), so nothing lifted it.
// The notes editor sits near the bottom of the form: once the keyboard rose it
// could never be scrolled into view, and the user typed blind.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/services/location_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_form_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo() : super(Dio());

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 9, 1);
    return Itinerary(
      id: id,
      userId: 'user-1',
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.onlyMe,
      createdAt: ts,
      updatedAt: ts,
      canEdit: true,
    );
  }
}

class _FakeMyProfile extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-1',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

/// No device fix, no permission prompt, no preview map.
class _NoLocation extends LocationService {
  @override
  Future<LocationOutcome> getCurrentLatLng() async => const LocationUnavailable();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('the notes editor is above the keyboard once it rises',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itineraryRepositoryProvider.overrideWithValue(_FakeRepo()),
          myProfileProvider.overrideWith(_FakeMyProfile.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          locationServiceProvider.overrideWithValue(_NoLocation()),
        ],
        child: MaterialApp(
          theme: buildNtripiTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          }),
        ),
      ),
    );

    // A bare push: on the root navigator, as in production, no shell above it.
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => const StopFormScreen(itineraryId: 'itin-1'),
    ));
    await tester.pumpAndSettle();

    // A new stop starts with its optional fields — the notes among them —
    // collapsed.
    final l10n =
        AppLocalizations.of(tester.element(find.byType(StopFormScreen)))!;
    final showOptional = find.text(l10n.showOptionalFields);
    await tester.ensureVisible(showOptional);
    await tester.tap(showOptional);
    await tester.pumpAndSettle();

    final notes = find.descendant(
      of: find.byType(MarkdownNotesEditor),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(notes);
    await tester.showKeyboard(notes);
    await tester.pumpAndSettle();

    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    expect(tester.getRect(notes).bottom, lessThanOrEqualTo(800 - keyboard),
        reason: 'the whole notes box must clear the keyboard');
  });
}
