// core/router/navigation_ext.dart — safe navigation, leaving and entering.
//
// The itinerary detail / stop routes live at the ROOT level (see the note in
// app_router.dart), so a `context.go()` into one of them REPLACES the whole
// match list instead of stacking onto it. The root navigator is then holding a
// single page, `canPop()` is false, and go_router's `pop()` throws
// `GoError: There is nothing to pop`.
//
// Three live paths reach a detail screen that way: creating an itinerary
// (itinerary_form_screen), deleting a stop (stop_form_screen — it deliberately
// skips past the stale stop page), and any cold start on a shared link. In all
// three the visible back button has nothing above it to return to.
//
// [popOr] is the only safe way for a custom back control to leave such a
// screen: pop when there is something to pop, otherwise navigate to the page
// that would have been underneath.
//
// Entering is the other half. A screen opened from outside the app — a
// notification tap — has to arrive with something beneath it, or it starts
// life as that dead end: go() left the tapped screen alone on its navigator,
// where the back arrow did nothing and Android's back closed the app.
// [NtripiEntryNavigation] holds the two ways in.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension NtripiNavigation on BuildContext {
  /// Pops the current route, or navigates to [fallbackLocation] when this
  /// route is the only one on its navigator.
  ///
  /// `canPop()` and `pop()` resolve against the same navigator chain, so the
  /// guard cannot disagree with the pop it protects.
  void popOr(String fallbackLocation) {
    if (canPop()) {
      pop();
    } else {
      go(fallbackLocation);
    }
  }
}

extension NtripiEntryNavigation on GoRouter {
  /// Opens [location] with home beneath it, as ONE navigation.
  ///
  /// Never `go('/profile/me')` and then `push(location)`: push() builds on the
  /// stack as it stands at the call, while go() lands only once the redirect's
  /// async secure-storage reads finish — so the push raced it, and could stack
  /// [location] on the splash page that go() was replacing.
  void pushOverHome(String location) {
    unawaited(
      routeInformationProvider.push(
        location,
        base: configuration.findMatch(Uri.parse('/profile/me')),
      ),
    );
  }

  /// Opens [location] over the screen the user left, so Back returns there and
  /// whatever they had typed survives.
  ///
  /// Only a root-level route can be stacked over anything — that is why those
  /// routes live at the root. A route inside the tab shell cannot: pushed over
  /// a root-level page, go_router appends a SECOND shell whose branch
  /// navigators collide with the first's keys (the freeze app_router.dart
  /// records). So a shell route opens over home instead.
  void openFromOutside(String location) {
    final insideShell = configuration
        .findMatch(Uri.parse(location))
        .matches
        .any((match) => match is ShellRouteMatch);
    if (insideShell) {
      pushOverHome(location);
    } else {
      unawaited(push(location));
    }
  }
}
