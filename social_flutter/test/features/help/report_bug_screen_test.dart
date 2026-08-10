// test/features/help/report_bug_screen_test.dart
//
// The screen's whole point is that it does NOT offer a way to file from here on
// mobile — filing would capture this screen rather than the broken one. These
// tests pin that, plus the two states where something else is true: web, where
// the button is the only way in, and gesture-off, where the instruction would
// otherwise be a lie.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/bug_report/providers/shake_report_enabled_provider.dart';
import 'package:social_flutter/features/help/presentation/report_bug_screen.dart';
import 'package:social_flutter/features/help/presentation/widgets/shake_phone_demo.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/l10n/app_localizations_en.dart';

final _en = AppLocalizationsEn();

class _FixedShakeEnabled extends ShakeReportEnabledNotifier {
  final bool initial;
  _FixedShakeEnabled(this.initial);

  @override
  bool build() => initial;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required bool forceWeb,
  bool gestureOn = true,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(500, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      shakeReportEnabledProvider
          .overrideWith(() => _FixedShakeEnabled(gestureOn)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: ReportBugScreen(forceWeb: forceWeb),
        ),
      ),
    ),
  );
  // pump, not pumpAndSettle: the shake demo repeats forever by design, so
  // settling would only ever time out. The reduce-motion test below is where
  // settling is the assertion.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('ReportBugScreen', () {
    testWidgets(
        'Given a mobile platform and the gesture on, '
        'Then it teaches the shake and offers no way to file from here',
        (tester) async {
      await _pumpScreen(tester, forceWeb: false);

      expect(find.text(_en.reportBugShakeBody), findsOneWidget);
      expect(find.byType(ShakePhoneDemo), findsOneWidget);
      expect(find.text(_en.reportBugShakeStep1), findsOneWidget);
      // "Shake your phone" is both the headline and step 2 — two by design.
      expect(find.text(_en.reportBugShakeStep2), findsNWidgets(2));
      expect(find.text(_en.reportBugShakeStep3), findsOneWidget);
      // The absence is the feature.
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.text(_en.reportBugGestureOff), findsNothing);
    });

    testWidgets(
        'Given a mobile platform and the gesture off, '
        'Then the off-notice and its switch appear, still with no button',
        (tester) async {
      await _pumpScreen(tester, forceWeb: false, gestureOn: false);

      expect(find.text(_en.reportBugGestureOff), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      // Still teaches the gesture — the switch is the fix, not a dead end.
      expect(find.text(_en.reportBugShakeBody), findsOneWidget);
    });

    testWidgets(
        'Given web, where there is no accelerometer, '
        'Then the button replaces the shake instruction', (tester) async {
      await _pumpScreen(tester, forceWeb: true);

      expect(find.text(_en.reportBugWebBody), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text(_en.reportBugShakeBody), findsNothing);
      expect(find.byType(ShakePhoneDemo), findsNothing);
    });

    testWidgets(
        'Given reduce motion is on, '
        'Then the demo holds a still frame instead of looping', (tester) async {
      await _pumpScreen(tester, forceWeb: false, reduceMotion: true);

      // pumpAndSettle completing at all is the assertion: a repeating
      // controller would time out here.
      await tester.pumpAndSettle();
      expect(find.byType(ShakePhoneDemo), findsOneWidget);
      expect(find.text(_en.reportBugShakeBody), findsOneWidget);
    });
  });
}
