// test/widgets/app_shell_tabs_test.dart — the tabs' bar: Feed and Profile at
// its two ends, the Profile tab showing the signed-in user's photo, and the bar
// moving down the side once the window has room for it beside the column.
//
// A tab opens the branch at its own index, so the bar's order and the router's
// branch order are one contract, checked from both sides. The photo is read
// from the profile TosGate already loads, under TosGate's gate — so signed
// out, nothing is read at all. Width alone decides where the bar is: crossing
// the line must never remount the open tab, or a resized window would lose its
// scroll position and whatever was being typed.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/cache/image_cache.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/router/app_router.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/profile_tab_icon.dart';

const _photoUrl = 'https://images.example/avatars/u1.jpg?v=3';
const _labels = ['Feed', 'Search', 'Itineraries', 'Saved', 'Profile'];

const _phone = Size(400, 800);
const _laptop = Size(1024, 768);

User _me({String? avatarUrl}) => User(
      id: 'u1',
      username: 'traveller',
      createdAt: DateTime(2026, 1, 1),
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      avatarUrl: avatarUrl,
    );

int _profileReads = 0;

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this.user);

  final User user;

  @override
  Future<User> build() async {
    _profileReads++;
    return user;
  }
}

/// The photo [cachedImageProvider] built, ready at once.
class _Photo extends ImageProvider<_Photo> {
  _Photo(this.url, this.image);

  final String url;
  final ui.Image image;

  @override
  Future<_Photo> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Photo key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

/// A tab with state worth keeping: something typed, a scrolled list.
class _TabBody extends StatefulWidget {
  const _TabBody();

  static int inits = 0;

  @override
  State<_TabBody> createState() => _TabBodyState();
}

class _TabBodyState extends State<_TabBody> {
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _TabBody.inits++;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            const TextField(key: Key('field')),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemExtent: 50,
                itemCount: 100,
                itemBuilder: (_, i) => Text('row $i'),
              ),
            ),
          ],
        ),
      );
}

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The real shell over five stand-in branches, one per tab; branch 0 has a
/// page below its top, to show that tapping the open tab goes back up.
Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  required bool signedIn,
  Size size = _phone,
  User? me,
  ui.Image? image,
  Locale? locale,
  bool online = true,
  Widget Function(int branch)? tab,
}) async {
  _window(tester, size);
  _profileReads = 0;
  final router = GoRouter(
    initialLocation: '/b0',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => appShellForTesting(shell),
        branches: [
          for (var i = 0; i < 5; i++)
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/b$i',
                builder: (_, _) => tab?.call(i) ?? Text('branch $i'),
                routes: [
                  GoRoute(path: 'deep', builder: (_, _) => Text('deep $i')),
                ],
              ),
            ]),
        ],
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      hasSessionProvider.overrideWith((ref) async => signedIn),
      myProfileProvider.overrideWith(() => _FakeMyProfile(me ?? _me())),
      if (image != null)
        cachedImageProvider.overrideWithValue((url) => _Photo(url, image)),
    ],
    child: MaterialApp.router(
      theme: buildNtripiTheme(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  test(
      'Given the app router, Then its tabs are Feed, Search, Itineraries, '
      'Saved and Profile, in that order', () {
    final shell =
        appRouter.configuration.routes.whereType<StatefulShellRoute>().single;

    expect(
      [for (final branch in shell.branches) (branch.routes.first as GoRoute).path],
      ['/feed', '/search', '/itineraries', '/saved', '/profile/me'],
    );
  });

  testWidgets(
      'Given the bar, Then it reads Feed, Search, Itineraries, Saved, Profile '
      'from left to right, and each tab opens the branch at its own index',
      (tester) async {
    await _pumpShell(tester, signedIn: false);

    final xs = [for (final l in _labels) tester.getCenter(find.text(l)).dx];
    expect(xs, [...xs]..sort());
    expect(xs.toSet(), hasLength(5));

    for (var i = _labels.length - 1; i >= 0; i--) {
      await tester.tap(find.text(_labels[i]));
      await tester.pumpAndSettle();
      expect(find.text('branch $i'), findsOneWidget);
    }
  });

  testWidgets(
      'Given a signed-in user with a photo, Then the Profile tab draws it in '
      'place of the person icon, and rings it in the bar\'s color once open',
      (tester) async {
    final image = (await tester.runAsync(() => createTestImage()))!;
    await _pumpShell(tester,
        signedIn: true, me: _me(avatarUrl: _photoUrl), image: image);

    final icon = tester.widget<ProfileTabIcon>(find.byType(ProfileTabIcon));
    expect((icon.photo! as _Photo).url, _photoUrl);
    expect(find.byIcon(Icons.person_outline_rounded), findsNothing);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(tester.widget<ProfileTabIcon>(find.byType(ProfileTabIcon)).selected,
        isTrue);
    final ring = tester
        .widget<DecoratedBox>(find.descendant(
          of: find.byType(ProfileTabIcon),
          matching: find.byType(DecoratedBox),
        ))
        .decoration as BoxDecoration;
    expect((ring.border as Border).top.color,
        tester.element(find.byType(ProfileTabIcon)).nt.forest);
  });

  testWidgets(
      'Given a signed-in user with no photo, Then the Profile tab keeps the '
      'person icon', (tester) async {
    await _pumpShell(tester, signedIn: true, me: _me());

    expect(_profileReads, 1);
    expect(tester.widget<ProfileTabIcon>(find.byType(ProfileTabIcon)).photo,
        isNull);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  testWidgets(
      'Given no session, Then the Profile tab shows the person icon and the '
      'profile is never read', (tester) async {
    await _pumpShell(tester,
        signedIn: false, me: _me(avatarUrl: _photoUrl));

    expect(_profileReads, 0);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  group('side bar', () {
    testWidgets(
        'Given a window 759 px wide, Then the tabs are along the bottom; '
        'Given 760 px, Then they are down the side', (tester) async {
      await _pumpShell(tester, signedIn: false, size: const Size(759, 800));
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      await _resize(tester, const Size(760, 800));
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.getSize(find.byType(NavigationRail)).width, kSideBarWidth);
    });

    testWidgets(
        'Given the side bar, Then it reads Feed, Search, Itineraries, Saved, '
        'Profile from top to bottom, and each tab opens the branch at its own '
        'index', (tester) async {
      await _pumpShell(tester, signedIn: false, size: _laptop);

      final ys = [for (final l in _labels) tester.getCenter(find.text(l)).dy];
      expect(ys, [...ys]..sort());
      expect(ys.toSet(), hasLength(5));
      // One column: every label sits on the bar's centre line.
      final xs = {for (final l in _labels) tester.getCenter(find.text(l)).dx};
      expect(xs, {kSideBarWidth / 2});

      for (var i = _labels.length - 1; i >= 0; i--) {
        await tester.tap(find.text(_labels[i]));
        await tester.pumpAndSettle();
        expect(find.text('branch $i'), findsOneWidget);
      }
    });

    testWidgets(
        'Given the side bar, When the open tab is tapped, Then it goes back to '
        'its top', (tester) async {
      final router = await _pumpShell(tester, signedIn: false, size: _laptop);
      router.go('/b0/deep');
      await tester.pumpAndSettle();
      expect(find.text('deep 0'), findsOneWidget);

      await tester.tap(find.text('Feed'));
      await tester.pumpAndSettle();

      expect(find.text('branch 0'), findsOneWidget);
      expect(find.text('deep 0'), findsNothing);
    });

    testWidgets(
        'Given the side bar, Then the tabs are centred on the window, so the '
        'column sits where a page without the bar puts it', (tester) async {
      await _pumpShell(
        tester,
        signedIn: false,
        size: _laptop,
        tab: (i) => SizedBox.expand(key: ValueKey('tab $i')),
      );

      final tabs = tester.getRect(find.byKey(const ValueKey('tab 0')));
      expect(tabs.left, kSideBarWidth);
      expect(tabs.center.dx, _laptop.width / 2);
    });

    testWidgets('Given Arabic, Then the side bar is on the right',
        (tester) async {
      await _pumpShell(tester,
          signedIn: false, size: _laptop, locale: const Locale('ar'));

      expect(tester.getRect(find.byType(NavigationRail)).right, _laptop.width);
    });

    testWidgets(
        'Given a signed-in user with a photo, Then the side bar draws it and '
        'rings it in the bar\'s color once open', (tester) async {
      final image = (await tester.runAsync(() => createTestImage()))!;
      await _pumpShell(tester,
          signedIn: true,
          size: _laptop,
          me: _me(avatarUrl: _photoUrl),
          image: image);

      final icon = tester.widget<ProfileTabIcon>(find.byType(ProfileTabIcon));
      expect((icon.photo! as _Photo).url, _photoUrl);
      expect(tester.getSize(find.byType(ProfileTabIcon)), const Size(24, 24));

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final ring = tester
          .widget<DecoratedBox>(find.descendant(
            of: find.byType(ProfileTabIcon),
            matching: find.byType(DecoratedBox),
          ))
          .decoration as BoxDecoration;
      expect((ring.border as Border).top.color,
          tester.element(find.byType(ProfileTabIcon)).nt.forest);
    });

    testWidgets(
        'When the window crosses 760 px either way, Then the open tab is not '
        'rebuilt: what was typed and how far it was scrolled both stay',
        (tester) async {
      _TabBody.inits = 0;
      await _pumpShell(
        tester,
        signedIn: false,
        size: _laptop,
        tab: (i) => i == 0 ? const _TabBody() : Text('branch $i'),
      );
      await tester.enterText(find.byKey(const Key('field')), 'typed');
      tester.state<_TabBodyState>(find.byType(_TabBody)).scroll.jumpTo(300);
      await tester.pump();

      for (final size in [const Size(700, 768), _laptop]) {
        await _resize(tester, size);

        expect(_TabBody.inits, 1);
        expect(find.text('typed'), findsOneWidget);
        expect(
            tester.state<_TabBodyState>(find.byType(_TabBody)).scroll.offset,
            300);
      }
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets(
        'Given a window too short for five tabs, Then the side bar scrolls to '
        'the last one instead of overflowing', (tester) async {
      await _pumpShell(tester, signedIn: false, size: const Size(1024, 200));
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Profile'),
        40,
        scrollable: find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('branch 4'), findsOneWidget);
    });

    testWidgets(
        'Given a banner over the tabs, Then the side bar does not leave room '
        'for the status bar a second time', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24);
      await _pumpShell(tester, signedIn: false, size: _laptop, online: false);

      final bannerBottom =
          tester.getRect(find.byIcon(Icons.wifi_off_rounded)).bottom;
      final firstTab = tester.getRect(find.byIcon(Icons.dynamic_feed)).top;
      expect(firstTab - bannerBottom, lessThan(24));
    });
  });
}
