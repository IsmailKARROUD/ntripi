// test/core/push/tap_routing_test.dart
//
// A notification tap never opens a screen with nothing beneath it.
//
// Regression: a tap while the app was in the background navigated with go(),
// which replaces the whole stack. The tapped screen — someone's profile, a
// trip, its ratings — was left alone on its navigator: the back arrow did
// nothing, Android's back closed the app, and the screen the user had left was
// destroyed. A cold start's go(home) + push(route) raced the redirect instead:
// push() builds on the stack as it stands at the call, go() lands only after
// the async redirect, so the push could end up stacked on the splash page.
//
// The router below has the app's three kinds of route — the tab shell,
// root-level routes, public routes — and an async redirect like the app's, so
// the go_router behaviour under test is the real one. The last test pins the
// app's own router to the same shape.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/auth/token_manager.dart';
import 'package:ntripi/core/push/push_gateway.dart';
import 'package:ntripi/core/push/push_service.dart';
import 'package:ntripi/core/router/app_router.dart';
import 'package:ntripi/core/services/sfx_service.dart';
import 'package:ntripi/features/auth/presentation/splash_screen.dart';
import 'package:ntripi/features/notifications/domain/app_notification.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// Every screen a notification can open, one entry per notification type.
final _taps = [
  for (final type in NotificationType.values)
    if (notificationRoute(type: type, actorId: 'u1', entityId: 'it1')
        case final route?)
      (type: type, route: route),
];

/// The destinations that live inside the tab shell — all in the Profile tab.
/// The last test holds the app's router to this.
const _inProfileTab = {'/follow-requests', '/settings/account-status'};

/// Splash warms the audio engine; nothing here may touch the plugin.
class _SilentSfx extends SfxService {
  _SilentSfx(super.ref);

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> play(Sfx sfx) async {}
}

GoRouter _router(String initialLocation, {Widget? splash}) {
  final root = GlobalKey<NavigatorState>();
  GoRoute page(String path, {GlobalKey<NavigatorState>? parent}) => GoRoute(
        path: path,
        parentNavigatorKey: parent,
        builder: (_, state) => Scaffold(
          body: Center(child: Text('at ${state.matchedLocation}')),
        ),
      );
  return GoRouter(
    navigatorKey: root,
    initialLocation: initialLocation,
    // Async and slow like the app's, which awaits two secure-storage reads —
    // the timing go() + push() lost to.
    redirect: (_, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return null;
    },
    routes: [
      if (splash == null)
        page('/splash')
      else
        GoRoute(path: '/splash', builder: (_, _) => splash),
      page('/login'),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => shell,
        branches: [
          StatefulShellBranch(routes: [page('/feed')]),
          StatefulShellBranch(routes: [
            page('/profile/me'),
            page('/follow-requests'),
            page('/settings/account-status'),
          ]),
        ],
      ),
      page('/itineraries/:id', parent: root),
      page('/itineraries/:id/ratings', parent: root),
      page('/profile/:userId', parent: root),
    ],
  );
}

Future<GoRouter> _pumpAt(WidgetTester tester, String location) async {
  final router = _router(location);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  expect(find.text('at $location'), findsOneWidget);
  return router;
}

Future<void> _back(WidgetTester tester, GoRouter router) async {
  router.pop();
  await tester.pumpAndSettle();
}

void main() {
  // A test that parks a tap for splash must not hand it to the next one.
  tearDown(() async => takeInitialPushRoute());

  group('Cold start — splash opens the tap over home', () {
    for (final tap in _taps) {
      testWidgets(
          'Given the app launched by a ${tap.type.name} tap, '
          'When splash finishes, '
          'Then ${tap.route} opens and Back lands on home, not on splash',
          (tester) async {
        FlutterSecureStorage.setMockInitialValues({
          'ntripi_refresh_token': 'refresh',
          'ntripi_refresh_expires_at': '2100-01-01T00:00:00Z',
        });
        // What getInitialMessage parks for the tap that launched the app.
        deferTapToSplash(tap.route);
        final router = _router('/splash', splash: const SplashScreen());
        await tester.pumpWidget(ProviderScope(
          overrides: [
            tokenManagerProvider.overrideWithValue(TokenManager(Dio())),
            sfxServiceProvider.overrideWith(_SilentSfx.new),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ));

        // The whole launch at 60 Hz, as on a device. Splash's loader keeps the
        // frames coming, and a frame landing before the redirect is what let
        // the old go() + push() fire its push early and stack the tap on
        // splash. pumpAndSettle alone steps 100 ms and never shows it.
        for (var t = 0; t < 2200; t += 16) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();

        expect(find.text('at ${tap.route}'), findsOneWidget);
        await _back(tester, router);
        expect(find.text('at /profile/me'), findsOneWidget);
        expect(router.canPop(), isFalse);
      });
    }
  });

  group('Warm start — the tap opens over the screen the user left', () {
    for (final tap in _taps) {
      final inShell = _inProfileTab.contains(tap.route);

      testWidgets(
          'Given the Feed tab, '
          'When a ${tap.type.name} tap opens ${tap.route}, '
          'Then Back returns to ${inShell ? 'home' : 'Feed'}', (tester) async {
        final router = await _pumpAt(tester, '/feed');

        openTappedRoute(router, tap.route);
        await tester.pumpAndSettle();

        expect(find.text('at ${tap.route}'), findsOneWidget);
        await _back(tester, router);
        expect(find.text(inShell ? 'at /profile/me' : 'at /feed'),
            findsOneWidget);
      });

      testWidgets(
          'Given a trip open over the tabs, '
          'When a ${tap.type.name} tap opens ${tap.route}, '
          'Then Back returns to ${inShell ? 'home' : 'the trip'}',
          (tester) async {
        final router = await _pumpAt(tester, '/feed');
        unawaited(router.push('/itineraries/open'));
        await tester.pumpAndSettle();

        openTappedRoute(router, tap.route);
        await tester.pumpAndSettle();

        // A shell route pushed over a root-level page duplicates the shell,
        // and the copies' navigator keys collide.
        expect(tester.takeException(), isNull);
        expect(find.text('at ${tap.route}'), findsOneWidget);
        await _back(tester, router);
        expect(find.text(inShell ? 'at /profile/me' : 'at /itineraries/open'),
            findsOneWidget);
      });
    }
  });

  group('Taps the app cannot open yet', () {
    testWidgets(
        'Given splash still up, When a tap arrives, '
        'Then it is handed to splash instead of navigated', (tester) async {
      final router = await _pumpAt(tester, '/splash');

      openTappedRoute(router, '/profile/u1');
      await tester.pumpAndSettle();

      expect(find.text('at /splash'), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(await takeInitialPushRoute(), '/profile/u1');
    });

    testWidgets(
        'Given a signed-out screen, When a tap arrives, '
        'Then nothing opens', (tester) async {
      final router = await _pumpAt(tester, '/login');

      openTappedRoute(router, '/profile/u1');
      await tester.pumpAndSettle();

      expect(find.text('at /login'), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(await takeInitialPushRoute(), isNull);
    });
  });

  testWidgets(
      'Given every notification type, '
      'When its destination is matched in the app router, '
      'Then it is a root-level route or a Profile-tab route', (tester) async {
    // pushOverHome stacks a shell route on /profile/me, inside the Profile
    // tab — right only for a route that lives in that tab.
    final config = appRouter.configuration;
    final home = config.findMatch(Uri.parse('/profile/me'));
    final profileTab = (home.matches.single as ShellRouteMatch).navigatorKey;

    for (final tap in _taps) {
      final match = config.findMatch(Uri.parse(tap.route));
      expect(match.isError, isFalse, reason: '${tap.route} is not a route');
      final shell = match.matches.whereType<ShellRouteMatch>().firstOrNull;
      if (_inProfileTab.contains(tap.route)) {
        expect(shell?.navigatorKey, same(profileTab),
            reason: '${tap.route} must live in the Profile tab');
      } else {
        expect(shell, isNull,
            reason: '${tap.route} is inside the tab shell: list it in '
                '_inProfileTab, or move it to the Profile tab or the root');
      }
    }
  });
}
