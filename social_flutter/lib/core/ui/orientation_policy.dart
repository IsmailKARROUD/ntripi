// core/ui/orientation_policy.dart — phones stay portrait; a tablet turns.
//
// A tablet's portrait lock no longer held anyway (Android 16 ignores it on
// large screens for apps targeting SDK 36, iPad while it can multitask), and
// the layout follows the width (core/ui/app_layout.dart), so a tablet turns
// and resizes freely. MainActivity.kt applies the same line before the first
// frame on Android.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A device whose shortest side is at least this many logical pixels is a
/// tablet — the line Android draws (sw600dp).
const double kTabletShortestSide = 600;

/// The orientations a device whose shortest side is [shortestSide] logical
/// pixels may take; an empty list lets it take any.
List<DeviceOrientation> allowedOrientations(double shortestSide) =>
    shortestSide < kTabletShortestSide
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : const [];

/// Applies [allowedOrientations] now and whenever the app's size changes — a
/// foldable opened up is a tablet.
class OrientationPolicy with WidgetsBindingObserver {
  OrientationPolicy._();

  bool? _tablet;

  /// Starts the policy. The web is never locked: the browser decides, and a
  /// phone browser turned sideways follows the width rule like any window.
  static Future<OrientationPolicy?> start() async {
    if (kIsWeb) return null;
    final policy = OrientationPolicy._();
    WidgetsBinding.instance.addObserver(policy);
    await policy._apply();
    return policy;
  }

  void stop() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeMetrics() => unawaited(_apply());

  Future<void> _apply() async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    // No size before the first metrics: guessing "phone" would flip a tablet
    // held sideways to portrait and back.
    if (view == null || view.physicalSize.isEmpty) return;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    final tablet = shortest >= kTabletShortestSide;
    // Metrics change on every keyboard frame; the answer rarely does.
    if (tablet == _tablet) return;
    _tablet = tablet;
    await SystemChrome.setPreferredOrientations(allowedOrientations(shortest));
  }
}
