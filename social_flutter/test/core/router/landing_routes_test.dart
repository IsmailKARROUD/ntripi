// test/core/router/landing_routes_test.dart
//
// On the web the address bar shows the screen on top (main.dart), so every
// route is a URL the app can be started on — a reload, a pasted address. Most
// screens can simply open there. An editing form cannot: it saves only under
// the edit claim the trip page takes before pushing it, and a fresh start holds
// none, so the router lands it on what it edits (editingRouteLanding).
//
// Every route of the app is classified below. A new route fails the suite
// until somebody decides which kind it is, the same way test_edit_guard_coverage
// holds the API's routes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/router/app_links.dart';
import 'package:ntripi/core/router/app_router.dart';

/// Screens the app may start on, as they are.
const _landable = {
  '/splash',
  '/login',
  '/register',
  '/forgot-password',
  '/suspended',
  '/search',
  '/search/profile/:userId',
  '/search/profile/:userId/followers',
  '/search/profile/:userId/following',
  '/profile/me',
  '/settings/change-password',
  '/settings/delete-account',
  '/settings/account-status',
  '/settings/blocked-users',
  '/follow-requests',
  '/notifications',
  '/settings/notifications',
  '/settings/help',
  '/settings/help/report-bug',
  '/settings/about',
  '/itineraries',
  '/saved',
  '/feed',
  // Creating claims nothing: a new trip has no claim to hold.
  '/itineraries/new',
  '/itineraries/:id',
  '/itineraries/:id/editors',
  '/itineraries/:id/ratings',
  '/itineraries/:id/ratings/:dimension',
  '/itineraries/:id/stops/:stopId',
  '/profile/:userId',
  '/profile/:userId/followers',
  '/profile/:userId/following',
  '/u/:username',
  '/unavailable/:kind',
};

/// Forms that save under an edit claim, or hand a result back to one: the app
/// never starts on them.
const _editing = {
  '/itineraries/:id/edit',
  '/itineraries/:id/stops/new',
  '/itineraries/:id/stops/:stopId/edit',
  '/map-picker',
};

/// Every GoRoute path of [routes], joined onto its parents'.
Iterable<String> _paths(List<RouteBase> routes, [String parent = '']) sync* {
  for (final route in routes) {
    if (route is GoRoute) {
      final path = route.path.startsWith('/')
          ? route.path
          : '${parent == '/' ? '' : parent}/${route.path}';
      yield path;
      yield* _paths(route.routes, path);
    } else {
      yield* _paths(route.routes, parent);
    }
  }
}

/// [path] with its parameters filled in, as a URL would carry them.
Uri _sample(String path) => Uri.parse(path
    .replaceAll(':id', '3fa85f64-5717-4562-b3fc-2c963f66afa6')
    .replaceAll(':stopId', '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d')
    .replaceAll(':userId', '1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed')
    .replaceAll(':username', 'aminad')
    .replaceAll(':dimension', 'safety')
    .replaceAll(':kind', 'trip'));

void main() {
  final live = _paths(appRouter.configuration.routes).toSet();

  test('every route of the app is classified', () {
    expect(_landable.intersection(_editing), isEmpty);
    expect(live.difference({..._landable, ..._editing}), isEmpty,
        reason: 'a new route: is it a place the app may start, or a form '
            'that saves under an edit claim?');
    expect({..._landable, ..._editing}.difference(live), isEmpty,
        reason: 'a classified route no longer exists');
  });

  test('an editing form lands on a screen the app may start on', () {
    for (final path in _editing) {
      final landing = editingRouteLanding(_sample(path));
      expect(landing, isNotNull, reason: path);
      final match = appRouter.configuration.findMatch(Uri.parse(landing!));
      expect(match.isError, isFalse, reason: '$path lands on $landing');
      expect(editingRouteLanding(Uri.parse(landing)), isNull, reason: path);
    }
  });

  test('every other screen opens as it is', () {
    for (final path in _landable) {
      expect(editingRouteLanding(_sample(path)), isNull, reason: path);
    }
  });

  test('the web address bar shows the screen on top', () {
    // Off, a reload on a trip opened from the feed lands on the feed, and the
    // bar of a shared trip shows home.
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('GoRouter.optionURLReflectsImperativeAPIs = true;'),
    );
  });
}
