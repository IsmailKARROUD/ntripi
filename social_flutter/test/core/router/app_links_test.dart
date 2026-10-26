// test/core/router/app_links_test.dart
//
// A shared link opens what it names, with something beneath it — and never
// lands as it arrives.
//
// A tap on https://ntripi.app/share/i/<id> reaches go_router as a navigation
// to its path: on a cold start as the platform's initial route, which would
// skip splash and its session restore; while running as a go(), which would
// replace the whole stack and destroy the screen the user was on.
// app_links.dart intercepts both. The router below has the app's kinds of
// route and an async redirect like the app's, wired to the same hooks the
// app's router uses; links are delivered the way the engine delivers them.
//
// On the web every screen has a URL of its own, so the app can start on any of
// them: the last groups hold where it then lands.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/auth/token_manager.dart';
import 'package:ntripi/core/router/app_links.dart';
import 'package:ntripi/core/router/app_router.dart';
import 'package:ntripi/core/services/sfx_service.dart';
import 'package:ntripi/features/auth/presentation/splash_screen.dart';
import 'package:ntripi/l10n/app_localizations.dart';

const _id = '3fa85f64-5717-4562-b3fc-2c963f66afa6';
const _tripLink = 'https://ntripi.app/share/i/$_id';
const _trip = '/itineraries/$_id';

/// Splash warms the audio engine; nothing here may touch the plugin.
class _SilentSfx extends SfxService {
  _SilentSfx(super.ref);

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> play(Sfx sfx) async {}
}

GoRouter _router({
  String initialLocation = '/splash',
  Widget? splash,
  bool signedIn = true,
  // The app's sign-in guard, asked at every navigation; null leaves it out.
  bool Function()? session,
}) {
  final root = GlobalKey<NavigatorState>();
  GoRoute page(String path, {GlobalKey<NavigatorState>? parent}) => GoRoute(
        path: path,
        parentNavigatorKey: parent,
        builder: (_, state) => Scaffold(
          body: Center(child: Text('at ${state.uri.path}')),
        ),
      );
  late final GoRouter router;
  router = GoRouter(
    navigatorKey: root,
    initialLocation: initialLocation,
    onEnter: appLinkOnEnter(hasSession: () async => signedIn),
    redirect: (_, state) async {
      final launch = appLinkLaunchRedirect(state);
      if (launch != null) return launch;
      final landing = editingRouteLaunchRedirect(router, state);
      if (landing != null) return landing;
      // Async and slow like the app's, which awaits two secure-storage reads.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (session != null &&
          !session() &&
          !const ['/splash', '/login'].contains(state.matchedLocation)) {
        return signInRedirect(state.uri);
      }
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
          StatefulShellBranch(routes: [page('/profile/me')]),
        ],
      ),
      page('/itineraries/:id', parent: root),
      page('/itineraries/:id/edit', parent: root),
      page('/itineraries/:id/stops/new', parent: root),
      page('/itineraries/:id/stops/:stopId', parent: root),
      page('/itineraries/:id/stops/:stopId/edit', parent: root),
      page('/map-picker', parent: root),
      page('/profile/:userId', parent: root),
      page('/u/:username', parent: root),
      page('/unavailable/:kind', parent: root),
    ],
  );
  return router;
}

/// The app started on [location] — on the web, a reload or a pasted address.
Future<GoRouter> _startAt(
  WidgetTester tester,
  String location, {
  bool Function()? session,
}) async {
  final router = _router(initialLocation: location, session: session);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  bool signedIn = true,
}) async {
  final router = _router(initialLocation: location, signedIn: signedIn);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  expect(find.text('at $location'), findsOneWidget);
  return router;
}

/// What the engine reports as the first route when [link] launched the app.
/// Set in the body: testWidgets resets it to '/' after setUp has run.
void _launchedBy(WidgetTester tester, String link) {
  tester.platformDispatcher.defaultRouteNameTestValue = link;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
}

/// What the engine does with a link tapped while the app runs.
Future<void> _tap(WidgetTester tester, String link) async {
  await tester.binding.handlePushRoute(link);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester, GoRouter router) async {
  router.pop();
  await tester.pumpAndSettle();
}

/// Pumps the whole launch through the real splash screen.
Future<GoRouter> _launchThroughSplash(WidgetTester tester) async {
  final router = _router(splash: const SplashScreen());
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
  // The brand flash at 60 Hz, as on a device.
  for (var t = 0; t < 2200; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
  return router;
}

void main() {
  // A link parked by one test must not open in the next.
  tearDown(takeParkedAppLink);

  group('appLinkLocation', () {
    test('a trip link opens the trip', () {
      expect(appLinkLocation(Uri.parse(_tripLink)), _trip);
    });

    test('a profile link opens the profile by handle', () {
      expect(
        appLinkLocation(Uri.parse('https://ntripi.app/share/u/amina.d_2')),
        '/u/amina.d_2',
      );
    });

    test('a query, a fragment or a trailing slash changes nothing', () {
      for (final link in [
        '$_tripLink?utm_source=whatsapp',
        '$_tripLink/',
        '$_tripLink#stops',
        '/share/i/$_id',
      ]) {
        expect(appLinkLocation(Uri.parse(link)), _trip, reason: link);
      }
    });

    test('a link that cannot name a trip is not available — and fetches '
        'nothing', () {
      for (final link in [
        'https://ntripi.app/share/i/3fa85f64-5717-4562', // cut short
        'https://ntripi.app/share/i/new', // never the create-trip form
        'https://ntripi.app/share/i/',
      ]) {
        expect(appLinkLocation(Uri.parse(link)), '/unavailable/trip',
            reason: link);
      }
      expect(appLinkLocation(Uri.parse('https://ntripi.app/share/u/')),
          '/unavailable/profile');
    });

    test('anything else is not a shared link', () {
      for (final link in [
        '/feed',
        _trip,
        '/profile/me',
        'https://ntripi.app/share/x/1',
        'https://ntripi.app/reset-password?token=t',
      ]) {
        expect(appLinkLocation(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  test('a parked link is handed out once', () {
    parkAppLink(_trip);
    expect(takeParkedAppLink(), _trip);
    expect(takeParkedAppLink(), isNull);
  });

  group('Cold start — splash opens the link over home', () {
    testWidgets(
        'Given the app launched by a trip link, When the router starts, '
        'Then splash shows and the trip waits for it', (tester) async {
      _launchedBy(tester, _tripLink);
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('at /splash'), findsOneWidget);
      expect(takeParkedAppLink(), _trip);
    });

    testWidgets(
        'Given a session, When splash finishes, '
        'Then the trip is open and Back lands on home', (tester) async {
      _launchedBy(tester, _tripLink);
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_refresh_token': 'refresh',
        'ntripi_refresh_expires_at': '2100-01-01T00:00:00Z',
      });
      final router = await _launchThroughSplash(tester);

      expect(find.text('at $_trip'), findsOneWidget);
      await _back(tester, router);
      expect(find.text('at /profile/me'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets(
        'Given no session, When splash finishes and the user signs in, '
        'Then the sign-in lands on the trip, over home', (tester) async {
      _launchedBy(tester, _tripLink);
      FlutterSecureStorage.setMockInitialValues({});
      final router = await _launchThroughSplash(tester);
      expect(find.text('at /login'), findsOneWidget);

      // What every sign-in path calls once it holds a session.
      landHome(router);
      await tester.pumpAndSettle();

      expect(find.text('at $_trip'), findsOneWidget);
      await _back(tester, router);
      expect(find.text('at /profile/me'), findsOneWidget);
    });
  });

  group('Warm start — the link opens over the screen the user is on', () {
    testWidgets(
        'Given the Feed tab, When a trip link is tapped, '
        'Then the trip opens and Back returns to Feed', (tester) async {
      final router = await _pumpAt(tester, '/feed');

      await _tap(tester, _tripLink);

      expect(find.text('at $_trip'), findsOneWidget);
      await _back(tester, router);
      expect(find.text('at /feed'), findsOneWidget);
    });

    testWidgets(
        'Given a trip open over the tabs, When a profile link is tapped, '
        'Then the profile opens over the trip', (tester) async {
      final router = await _pumpAt(tester, '/feed');
      unawaited(router.push(_trip));
      await tester.pumpAndSettle();

      await _tap(tester, 'https://ntripi.app/share/u/aminad');

      expect(tester.takeException(), isNull);
      expect(find.text('at /u/aminad'), findsOneWidget);
      await _back(tester, router);
      expect(find.text('at $_trip'), findsOneWidget);
    });

    testWidgets(
        'Given the trip already open, When its link is tapped again, '
        'Then it is not stacked twice', (tester) async {
      final router = await _pumpAt(tester, '/feed');
      await _tap(tester, _tripLink);

      await _tap(tester, _tripLink);

      await _back(tester, router);
      expect(find.text('at /feed'), findsOneWidget);
    });

    testWidgets(
        'Given the Feed tab, When a cut-short link is tapped, '
        'Then the not-available page opens over Feed', (tester) async {
      final router = await _pumpAt(tester, '/feed');

      await _tap(tester, 'https://ntripi.app/share/i/3fa85f64');

      expect(find.text('at /unavailable/trip'), findsOneWidget);
      await _back(tester, router);
      expect(find.text('at /feed'), findsOneWidget);
    });
  });

  group('Links the app cannot open yet wait instead of being lost', () {
    testWidgets(
        'Given splash still up, When a link is tapped, '
        'Then it is parked for splash instead of navigated', (tester) async {
      final router = await _pumpAt(tester, '/splash');

      await _tap(tester, _tripLink);

      expect(find.text('at /splash'), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(takeParkedAppLink(), _trip);
    });

    testWidgets(
        'Given a signed-out screen, When a link is tapped, '
        'Then nothing opens until the sign-in, which lands on it',
        (tester) async {
      final router = await _pumpAt(tester, '/login', signedIn: false);

      await _tap(tester, _tripLink);
      expect(find.text('at /login'), findsOneWidget);
      expect(router.canPop(), isFalse);

      landHome(router);
      await tester.pumpAndSettle();
      expect(find.text('at $_trip'), findsOneWidget);
    });
  });

  group('parkableLocation', () {
    test('a trip or a profile waits for the sign-in', () {
      expect(parkableLocation(Uri.parse(_trip)), _trip);
      expect(parkableLocation(Uri.parse('/u/amina.d_2')), '/u/amina.d_2');
      expect(parkableLocation(Uri.parse('/profile/$_id')), '/profile/$_id');
      expect(parkedLinkKind('/profile/$_id'), ParkedLinkKind.profile);
    });

    test('nothing else does — home least of all', () {
      for (final location in [
        '/profile/me',
        '/feed',
        '/itineraries/new',
        '/itineraries/$_id/edit',
        '/itineraries/3fa85f64',
        '/settings/help',
      ]) {
        expect(parkableLocation(Uri.parse(location)), isNull,
            reason: location);
      }
      expect(parkedLinkKind('/profile/me'), isNull);
    });
  });

  group('editingRouteLanding', () {
    test('an editing form lands on what it edits', () {
      const stop = '3fa85f64-0000-4562-b3fc-2c963f66afa6';
      expect(editingRouteLanding(Uri.parse('$_trip/edit')), _trip);
      expect(editingRouteLanding(Uri.parse('$_trip/stops/new')), _trip);
      expect(editingRouteLanding(Uri.parse('$_trip/stops/$stop/edit')),
          '$_trip/stops/$stop');
      // It hands a place back to the form that pushed it; alone, to nobody.
      expect(editingRouteLanding(Uri.parse('/map-picker')), '/profile/me');
    });

    test('every other screen is a place to start', () {
      for (final location in [
        _trip,
        '/itineraries/new',
        '$_trip/stops/3fa85f64-0000-4562-b3fc-2c963f66afa6',
        '$_trip/ratings',
        '$_trip/editors',
        '/profile/me',
        '/u/aminad',
      ]) {
        expect(editingRouteLanding(Uri.parse(location)), isNull,
            reason: location);
      }
    });
  });

  group('A reload never starts the app on an editing form', () {
    testWidgets(
        'Given a reload on the trip\'s edit form, When the app starts, '
        'Then the trip opens instead', (tester) async {
      await _startAt(tester, '$_trip/edit');

      expect(find.text('at $_trip'), findsOneWidget);
    });

    testWidgets(
        'Given a reload on a stop\'s edit form, When the app starts, '
        'Then that stop\'s page opens instead', (tester) async {
      const stop = '/stops/3fa85f64-0000-4562-b3fc-2c963f66afa6';
      await _startAt(tester, '$_trip$stop/edit');

      expect(find.text('at $_trip$stop'), findsOneWidget);
    });

    testWidgets(
        'Given a reload on the map picker, When the app starts, '
        'Then home opens instead', (tester) async {
      await _startAt(tester, '/map-picker');

      expect(find.text('at /profile/me'), findsOneWidget);
    });

    testWidgets(
        'Given the app running, When the trip page pushes its edit form, '
        'Then the form opens — the claim was taken first', (tester) async {
      final router = await _pumpAt(tester, '/feed');

      unawaited(router.push('$_trip/edit'));
      await tester.pumpAndSettle();

      expect(find.text('at $_trip/edit'), findsOneWidget);
    });
  });

  group('A trip or profile URL opened signed out waits for the sign-in', () {
    for (final location in [_trip, '/u/aminad', '/profile/$_id']) {
      testWidgets(
          'Given nobody signed in, When the app starts on $location, '
          'Then the sign-in lands on it, over home', (tester) async {
        var signedIn = false;
        final router =
            await _startAt(tester, location, session: () => signedIn);
        expect(find.text('at /login'), findsOneWidget);
        expect(parkedAppLink.value, location);

        // What every sign-in path does once it holds a session.
        signedIn = true;
        landHome(router);
        await tester.pumpAndSettle();

        expect(find.text('at $location'), findsOneWidget);
        await _back(tester, router);
        expect(find.text('at /profile/me'), findsOneWidget);
      });
    }

    testWidgets(
        'Given nobody signed in, When the app starts on a tab, '
        'Then the sign-in waits for nothing', (tester) async {
      await _startAt(tester, '/feed', session: () => false);

      expect(find.text('at /login'), findsOneWidget);
      expect(takeParkedAppLink(), isNull);
    });
  });

  group('The web address bar shows the screen on top', () {
    setUp(() => GoRouter.optionURLReflectsImperativeAPIs = true);
    tearDown(() => GoRouter.optionURLReflectsImperativeAPIs = false);

    testWidgets(
        'Given a session and a trip link that started the app, '
        'When splash opens it over home, Then the URL is the trip\'s, '
        'and home\'s again after Back', (tester) async {
      _launchedBy(tester, _tripLink);
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_refresh_token': 'refresh',
        'ntripi_refresh_expires_at': '2100-01-01T00:00:00Z',
      });
      final router = await _launchThroughSplash(tester);

      expect(find.text('at $_trip'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, _trip);

      await _back(tester, router);
      expect(router.routeInformationProvider.value.uri.path, '/profile/me');
    });
  });

  testWidgets(
      'Given every place a shared link can open, '
      'When it is matched in the app router, '
      'Then it is a root-level route', (tester) async {
    // openFromOutside stacks a root-level route over anything; a route inside
    // the tab shell would land on home instead of over the user's screen.
    final config = appRouter.configuration;
    for (final link in [
      _tripLink,
      'https://ntripi.app/share/u/aminad',
      'https://ntripi.app/share/i/new',
      'https://ntripi.app/share/u/',
    ]) {
      final location = appLinkLocation(Uri.parse(link))!;
      final match = config.findMatch(Uri.parse(location));
      expect(match.isError, isFalse, reason: '$location is not a route');
      expect(match.matches.whereType<ShellRouteMatch>(), isEmpty,
          reason: '$location must live at the root');
    }
  });
}
