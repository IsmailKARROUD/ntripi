// test/widgets/profile_wide_layout_test.dart — a profile on a wide window.
//
// The Followers / Following counts join the name's row when they fit: each
// count beside its label on one line, the name, Followers and Following evenly
// apart, the counts level with the @handle. When they do not fit they drop
// below the name, each count above its label — the phone layout. Passport,
// Lives in and Speaks are the one part of a profile not held to the column:
// once their row is the wider, it is centred on the window, as the column is.

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

/// The test font draws every character 1 em wide, about twice DM Sans: with
/// Chinese labels "Amina" leaves room for the counts in a 600 px column, and a
/// 20-character name does not.
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
  Locale? locale,
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
      locale: locale,
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

/// A count and its label on one line, as the name's row shows them.
Rect _inline(WidgetTester tester, String text) =>
    tester.getRect(find.text(text, findRichText: true));

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
      'Given a wide window, Then each count stands beside its label on one '
      'line, the name, Followers and Following evenly apart, the counts level '
      'with the @handle and the last against the column\'s edge',
      (tester) async {
    await _pump(tester, width: 1024, locale: const Locale('zh'));

    expect(_countsBesideName(tester), isTrue);
    final name = tester.getRect(find.text('Amina'));
    final handle = tester.getRect(find.text('@aminad'));
    final followers = _inline(tester, '247 粉丝');
    final following = _inline(tester, '38 关注');
    final gap = followers.left - name.right;
    expect(following.left - followers.right, moreOrLessEquals(gap));
    expect(gap, greaterThanOrEqualTo(24));
    expect(followers.bottom, moreOrLessEquals(handle.bottom));
    expect(following.bottom, moreOrLessEquals(handle.bottom));
    // The column is 600 px centred on 1024: 212 to 812.
    expect(following.right, 812 - 16);
  });

  testWidgets(
      'Given a phone, Then the counts drop below the name, each above its '
      'label, as they always have', (tester) async {
    await _pump(tester, width: 390);

    expect(_countsBesideName(tester), isFalse);
    final avatar = tester.getRect(find.byType(AvatarWithBadge));
    final count = tester.getRect(find.text('247'));
    final label = tester.getRect(find.text('Followers'));
    expect(count.top, greaterThan(avatar.bottom));
    expect(label.top, greaterThanOrEqualTo(count.bottom));
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
      'three share one row centred on the window, wider than the column, '
      'while the rest of the profile keeps to the column', (tester) async {
    await _pump(tester, width: 1440, besideSideBar: true);

    final passport = _card(tester, 'PASSPORT');
    final livesIn = _card(tester, 'LIVES IN');
    final speaks = _card(tester, 'SPEAKS');
    expect({passport.top, livesIn.top, speaks.top}, hasLength(1));
    expect((passport.left + speaks.right) / 2, moreOrLessEquals(720));
    // The column is 600 px centred on the window: 420 to 1020.
    expect(passport.left, lessThan(420));
    expect(speaks.right, greaterThan(1020));
    expect(tester.getRect(find.byType(AvatarWithBadge)).left, 420 + 16);
  });

  testWidgets(
      'Given a phone, Then passport, residence and languages start where the '
      'bio does, as they always have', (tester) async {
    await _pump(tester, width: 390);

    expect(_card(tester, 'PASSPORT').left, 16);
  });
}
