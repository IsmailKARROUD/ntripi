// core/router/app_links.dart — shared links that open the app.
//
// A tap on https://ntripi.app/share/i/<id> or /share/u/<name> opens the app
// when it is installed: AndroidManifest.xml's autoVerify intent filter and the
// applinks: entitlement claim exactly those paths, and the server's
// /.well-known files vouch for the app (social_api services/app_links.py).
// Flutter's own deep linking then hands the URL to go_router as a navigation
// to its path — on a cold start as the initial location, on a warm one as a
// platform push.
//
// Neither may land as it arrives. A cold start's would skip splash — the
// session restore, and home beneath the target so Back has somewhere to go.
// A warm one's is a go(), which replaces the stack and destroys the screen the
// user was on, unsaved text and all. So:
//   * cold start — the redirect parks the link and sends the app to /splash,
//     which opens it over home (landHome), exactly as it opens a tray tap;
//   * splash still up, or nobody signed in — parked, and opened by splash or
//     by the sign-in that follows. Unlike a tray tap it is not dropped when
//     signed out: a link belongs to no session;
//   * otherwise — opened over the current screen (openFromOutside).
//
// The claimed paths are one contract across four places — the manifest, the
// entitlements (host only), the server's apple-app-site-association, and
// [appLinkLocation] — held together by test/app_links_native_config_test.dart.

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/router/navigation_ext.dart';
import 'package:ntripi/core/storage/secure_storage.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The in-app location a shared link opens, or null if [uri] is not one.
///
/// Scheme and host are ignored: the platform has already decided the link is
/// ours, and the web build sees the same paths under `/app/#`.
String? appLinkLocation(Uri uri) {
  final segments = [
    for (final segment in uri.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  if (segments.length < 2 || segments.first != 'share') return null;
  final target = segments.length > 2 ? segments[2] : '';
  return switch (segments[1]) {
    // Checked before anything is fetched: a cut-short id can never be a trip,
    // and `new` must never open the create-trip form.
    'i' => _uuid.hasMatch(target)
        ? '/itineraries/$target'
        : '/unavailable/trip',
    'u' => target.isEmpty
        ? '/unavailable/profile'
        : '/u/${Uri.encodeComponent(target)}',
    _ => null,
  };
}

/// What a parked link opens.
enum ParkedLinkKind { trip, profile }

/// The kind of [location] — one of [appLinkLocation]'s answers — or null.
ParkedLinkKind? parkedLinkKind(String? location) {
  if (location == null) return null;
  if (location.startsWith('/itineraries/') || location == '/unavailable/trip') {
    return ParkedLinkKind.trip;
  }
  if (location.startsWith('/u/') || location == '/unavailable/profile') {
    return ParkedLinkKind.profile;
  }
  return null;
}

// A notifier rather than a bare field so the sign-in screens can say what is
// waiting behind them, including for a link that arrives while they are open.
final _parked = ValueNotifier<String?>(null);

/// Keeps [location] for the next landing — splash's, or the next sign-in's.
void parkAppLink(String location) => _parked.value = location;

/// The parked link, if any. Consumes it, so it opens once.
String? takeParkedAppLink() {
  final parked = _parked.value;
  _parked.value = null;
  return parked;
}

/// The parked link without consuming it, for the sign-in screens' notice
/// (ParkedLinkNotice). Notifies when a link is parked or taken.
ValueListenable<String?> get parkedAppLink => _parked;

/// The redirect's first step. A shared link reaching it launched the app — the
/// only kind [appLinkOnEnter] lets through — so it is parked, and the app goes
/// to splash, which restores the session and opens it over home.
String? appLinkLaunchRedirect(GoRouterState state) {
  final location = appLinkLocation(state.uri);
  if (location == null) return null;
  parkAppLink(location);
  return '/splash';
}

/// The router's `onEnter`: decides where a shared link goes (see the top of
/// this file). [hasSession] is a seam for tests.
OnEnter appLinkOnEnter({
  Future<bool> Function() hasSession = hasLiveRefreshToken,
}) {
  return (context, current, next, router) async {
    final location = appLinkLocation(next.uri);
    if (location == null) return const Allow();
    // Cold start: there is nothing to open it over yet — the redirect parks it.
    if (router.routerDelegate.currentConfiguration.isEmpty) {
      return const Allow();
    }
    // `current` is the visible page — the top of any pushed stack, unlike the
    // match list's own uri, which stays at the route the pushes sit on.
    final here = current.uri.path;
    // Splash would replace anything opened now, and nobody signed in can open
    // it at all — so it waits for whichever lands next.
    if (here == '/splash' || !await hasSession()) {
      parkAppLink(location);
      return const Block.stop();
    }
    // The same link tapped twice opens it once.
    if (here == location) return const Block.stop();
    return Block.then(() => router.openFromOutside(location));
  };
}

/// Where the app lands after splash or a sign-in: on [pushRoute] (the tray tap
/// that launched it) or a parked link, with home beneath — otherwise on home.
void landHome(GoRouter router, {String? pushRoute}) {
  // Consumed either way: one launch, one landing.
  final link = takeParkedAppLink();
  final route = pushRoute ?? link;
  if (route == null) {
    router.go('/profile/me');
  } else {
    // One navigation, never go() then push() — see pushOverHome.
    router.pushOverHome(route);
  }
}
