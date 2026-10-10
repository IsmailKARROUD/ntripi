// test/widgets/saving_overlay_test.dart
//
// Isolated widget tests for SavingOverlay.
// Covers: no overlay when idle, blur + loader when saving, that the overlay
// swallows taps aimed at widgets underneath it, and the optional message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

Widget _host({
  required bool saving,
  required VoidCallback onTap,
  String? message,
}) {
  return MaterialApp(
    home: SavingOverlay(
      saving: saving,
      message: message,
      child: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: onTap,
            child: const Text('Save'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SavingOverlay', () {
    testWidgets(
        'Given saving is false, '
        'Then no blur or loader is shown and the child stays tappable',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(saving: false, onTap: () => tapped++));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(NTripiRingLoader), findsNothing);

      await tester.tap(find.text('Save'));
      expect(tapped, 1);
    });

    testWidgets(
        'Given saving is true, '
        'Then the blur overlay and loader are shown', (tester) async {
      await tester.pumpWidget(_host(saving: true, onTap: () {}));

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(NTripiRingLoader), findsOneWidget);
      expect(find.byType(AbsorbPointer), findsWidgets);
    });

    testWidgets(
        'Given saving is true, '
        'Then taps on widgets behind the overlay do not fire', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(saving: true, onTap: () => tapped++));

      // warnIfMissed: false — the button is intentionally obstructed.
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(tapped, 0);
    });

    testWidgets(
        'Given a message, Then it is shown under the loader and announced, '
        'and only while saving', (tester) async {
      const message = 'Saving your changes…';
      await tester.pumpWidget(
          _host(saving: true, onTap: () {}, message: message));

      expect(find.text(message), findsOneWidget);
      expect(find.byType(NTripiRingLoader), findsOneWidget);
      final announced = tester.widget<Semantics>(find
          .ancestor(of: find.text(message), matching: find.byType(Semantics))
          .first);
      expect(announced.properties.liveRegion, isTrue);

      await tester.pumpWidget(
          _host(saving: false, onTap: () {}, message: message));
      expect(find.text(message), findsNothing);
    });
  });
}
