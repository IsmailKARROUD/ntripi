// test/widgets/app_shell_tabs_test.dart — the bottom bar: Feed and Profile at
// its two ends, and the Profile tab showing the signed-in user's photo.
//
// A tab opens the branch at its own index, so the bar's order and the router's
// branch order are one contract, checked from both sides. The photo is read
// from the profile TosGate already loads, under TosGate's gate — so signed
// out, nothing is read at all.

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

/// The real shell over five stand-in branches, one per tab.
Future<void> _pumpShell(
  WidgetTester tester, {
  required bool signedIn,
  User? me,
  ui.Image? image,
}) async {
  _profileReads = 0;
  final router = GoRouter(
    initialLocation: '/b0',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => appShellForTesting(shell),
        branches: [
          for (var i = 0; i < 5; i++)
            StatefulShellBranch(routes: [
              GoRoute(path: '/b$i', builder: (_, _) => Text('branch $i')),
            ]),
        ],
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      hasSessionProvider.overrideWith((ref) async => signedIn),
      myProfileProvider.overrideWith(() => _FakeMyProfile(me ?? _me())),
      if (image != null)
        cachedImageProvider.overrideWithValue((url) => _Photo(url, image)),
    ],
    child: MaterialApp.router(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
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
}
