// core/router/navigation_ext.dart — safe back-navigation.
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
