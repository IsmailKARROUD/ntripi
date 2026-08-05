// features/bug_report/presentation/shake_to_report.dart
//
// Listens for a physical shake and opens the bug reporter. Wraps the whole app
// from MaterialApp.builder, so the gesture works on every screen including
// login and the suspended-account screen.
//
// Everything here exists to keep the gesture from firing when the user did not
// mean it — an accelerometer trigger that goes off in a pocket or a car is the
// version of this feature people uninstall over.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shake/shake.dart';
import 'package:social_flutter/core/router/app_router.dart';
import 'package:social_flutter/features/bug_report/presentation/bug_report_entry.dart';
import 'package:social_flutter/features/bug_report/providers/shake_report_enabled_provider.dart';

/// How long after one shake before another can open the reporter. Covers the
/// dismissal animation, so a lingering shake cannot immediately reopen it.
const _cooldown = Duration(seconds: 3);

class ShakeToReport extends ConsumerStatefulWidget {
  final Widget child;

  const ShakeToReport({super.key, required this.child});

  @override
  ConsumerState<ShakeToReport> createState() => _ShakeToReportState();
}

class _ShakeToReportState extends ConsumerState<ShakeToReport>
    with WidgetsBindingObserver {
  ShakeDetector? _detector;
  DateTime? _lastShake;

  @override
  void initState() {
    super.initState();
    // Web has no accelerometer worth listening to, and sensors_plus needs an
    // explicit DeviceMotion permission prompt on iOS Safari. The Settings row
    // is the entry point there.
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    _detector = ShakeDetector.autoStart(
      onPhoneShake: (_) => _onShake(),
      // Two shakes rather than the default one: a single spike is a phone
      // being set down, picked up, or jostled while walking.
      minimumShakeCount: 2,
      shakeSlopTimeMS: 500,
    );
  }

  @override
  void dispose() {
    _detector?.stopListening();
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keeps the accelerometer stream off the battery while backgrounded, and
    // stops a shake during a phone call from queueing up a report.
    if (state == AppLifecycleState.resumed) {
      _detector?.startListening();
    } else {
      _detector?.stopListening();
    }
  }

  void _onShake() {
    if (!mounted) return;
    if (!ref.read(shakeReportEnabledProvider)) return;

    final now = DateTime.now();
    if (_lastShake != null && now.difference(_lastShake!) < _cooldown) return;

    // Nothing to report from the splash screen — the user has not seen the app
    // yet, and the screenshot would just be the logo.
    if (appRouter.routerDelegate.currentConfiguration.uri.path == '/splash') {
      return;
    }

    _lastShake = now;
    startBugReport(context, ref);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
