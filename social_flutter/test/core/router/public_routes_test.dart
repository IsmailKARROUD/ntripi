// test/core/router/public_routes_test.dart
//
// Without an account the app shows only these screens; everything else
// redirects to /login. That is the client half of "a reader without an account
// reaches the teaser and nothing else" — the share pages are the server half,
// held by social_api's test_public_surface.py. A screen added here would show
// its content to anyone, so the list is pinned: changing it is a decision, and
// this test makes it a visible one.

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/router/app_router.dart';

void main() {
  test('only the sign-in screens are reachable signed out', () {
    expect(kPublicRoutes, unorderedEquals(const [
      '/login',
      '/register',
      '/splash',
      '/forgot-password',
      '/suspended',
    ]));
  });
}
