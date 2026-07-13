// test/widgets/offline_gate_test.dart
//
// Isolated widget tests for OfflineGate.
// Covers: pass-through when online, disabled child + blocked taps when
// offline, and the "you're offline" popover shown on a blocked tap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

Widget _host({required bool online, required VoidCallback onTap}) {
  return ProviderScope(
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: OfflineGate(
            builder: (isOnline) => FilledButton(
              onPressed: isOnline ? onTap : null,
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('OfflineGate', () {
    testWidgets(
        'Given device is online, '
        'Then the child callback fires on tap and no popover appears',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(online: true, onTap: () => tapped++));
      await tester.pump(); // let the connectivity stream emit

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(tapped, 1);
      expect(find.text("You're offline"), findsNothing);
    });

    testWidgets(
        'Given device is offline, '
        'Then the child is disabled and its callback never fires',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(online: false, onTap: () => tapped++));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull); // native disabled styling

      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, 0);
    });

    testWidgets(
        'Given device is offline, '
        'Then tapping the gated control shows the offline popover',
        (tester) async {
      await tester.pumpWidget(_host(online: false, onTap: () {}));
      await tester.pump();

      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsOneWidget);
    });
  });
}
