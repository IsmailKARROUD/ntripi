// test/widgets/profile_wide_layout_test.dart — a profile on a wide window.
//
// The Followers / Following counts join the name's row when both fit, and
// drop below it — the phone layout — when they do not. Passport, Lives in and
// Speaks are the one part of a profile not held to the column: their row runs
// from the side bar to the screen's far edge, so all three can share a line.
// Everything else stays in the column, centred on the window.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/profile/domain/visited_location.dart';
import 'package:ntripi/features/profile/presentation/profile_screen.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_chrome.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/profile/providers/user_locations_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/content_column.dart';
import 'package:ntripi/shared/widgets/side_by_side_when_fits.dart';

// ignore_for_file: invalid_use_of_internal_member

const _userId = 'other-1';

/// The test font draws every character 1 em wide, so "Amina" leaves room for
/// the counts in a 600 px column and a 20-character name does not.
User _user({String displayName = 'Amina'}) => User(
      id: _userId,
      username: 'aminad',
      displayName: displayName,
      isPrivate: false,
      followersCount: 247,
      followingCount: 38,
      createdAt: DateTime(2024),
      passportCountries: const ['US', 'GB', 'ZA', 'DE'],
      residentCountry: 'BE',
      languages: const ['fr', 'ar', 'en'],
    );

class _FakeUserProfile extends UserProfileNotifier {
  _FakeUserProfile(this._user) : super('');
  final User _user;
  @override
  Future<User> build() async => _user;
}

class _NoItineraries extends UserItinerariesNotifier {
  _NoItineraries() : super('');
  @override
  Future<List<Itinerary>> build() async => const [];
}

class _NoLocations extends UserLocationsNotifier {
  _NoLocations() : super('');
  @override
  Future<List<VisitedLocation>> build() async => const [];
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  User? user,
  bool besideSideBar = false,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({});
  const screen = ProfileScreen(userId: _userId);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      userProfileProvider.overrideWith2((_) => _FakeUserProfile(user ?? _user())),
      userItinerariesProvider.overrideWith2((_) => _NoItineraries()),
      userLocationsProvider.overrideWith2((_) => _NoLocations()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Where the tabs' shell puts a screen beside its side bar.
      home: besideSideBar
          ? Row(children: [
              const SizedBox(width: kSideBarWidth),
              Expanded(
                child: SideBarInset(width: kSideBarWidth, child: screen),
              ),
            ])
          : screen,
    ),
  ));
  await tester.pump();
}

bool _countsBesideName(WidgetTester tester) => tester
    .renderObject<RenderSideBySideWhenFits>(find.byType(SideBySideWhenFits))
    .sideBySide;

/// The card a fact's label sits in.
Rect _card(WidgetTester tester, String label) => tester.getRect(find
    .ancestor(of: find.text(label), matching: find.byType(Container))
    .first);

void main() {
  // OSM tiles fail with HTTP 400 under test, as in user_profile_screen_test.
  setUp(() {
    final orig = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == 'image resource service') return;
      orig?.call(details);
    };
    addTearDown(() => FlutterError.onError = orig);
  });

  testWidgets(
      'Given a wide window, Then Followers and Following sit at the end of '
      'the name\'s row, inside the column', (tester) async {
    await _pump(tester, width: 1024);

    expect(_countsBesideName(tester), isTrue);
    final avatar = tester.getRect(find.byType(AvatarWithBadge));
    final name = tester.getRect(find.text('Amina'));
    final followers = tester.getRect(find.text('Followers'));
    final following = tester.getRect(find.text('Following'));
    expect(followers.left, greaterThan(name.right));
    expect(followers.bottom, lessThanOrEqualTo(avatar.bottom));
    expect(following.top, followers.top);
    // The column is 600 px centred on 1024: 212 to 812.
    expect(avatar.left, 212 + 16);
    expect(following.right, lessThanOrEqualTo(812));
  });

  testWidgets(
      'Given a phone, Then the counts drop below the name, as they always '
      'have', (tester) async {
    await _pump(tester, width: 390);

    expect(_countsBesideName(tester), isFalse);
    expect(tester.getRect(find.text('Followers')).top,
        greaterThan(tester.getRect(find.byType(AvatarWithBadge)).bottom));
  });

  testWidgets(
      'Given a name too long to leave room for the counts, Then they drop '
      'below it, wide window or not', (tester) async {
    await _pump(tester,
        width: 1024, user: _user(displayName: 'Amina Diallo Senegal'));

    expect(_countsBesideName(tester), isFalse);
    expect(tester.getRect(find.text('Followers')).top,
        greaterThan(tester.getRect(find.byType(AvatarWithBadge)).bottom));
  });

  testWidgets(
      'Given passport, residence and languages beside the side bar, Then the '
      'three share one row that starts at the side bar and runs past the '
      'column, while the rest of the profile keeps to the column',
      (tester) async {
    await _pump(tester, width: 1440, besideSideBar: true);

    final passport = _card(tester, 'PASSPORT');
    final livesIn = _card(tester, 'LIVES IN');
    final speaks = _card(tester, 'SPEAKS');
    expect(passport.left, kSideBarWidth + 16);
    expect({passport.top, livesIn.top, speaks.top}, hasLength(1));
    // The column is 600 px centred on the window: 420 to 1020.
    expect(speaks.right, greaterThan(1020));
    expect(speaks.right, lessThanOrEqualTo(1440 - 16));
    expect(tester.getRect(find.byType(AvatarWithBadge)).left, 420 + 16);
  });
}
