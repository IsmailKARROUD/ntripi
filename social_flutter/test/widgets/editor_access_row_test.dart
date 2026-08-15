// test/widgets/editor_access_row_test.dart — an editor's way out of a trip.
//
// The row itself holds no permission logic (the detail screen owns the gate),
// so what is worth pinning here is that the action is wired, that it fires once
// rather than on any stray tap on the card, and that a leave already in flight
// cannot be fired twice.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/editor_access_row.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('EditorAccessRow', () {
    testWidgets('Given an editor, When built, Then it states the access and offers the exit',
        (tester) async {
      await tester.pumpWidget(_wrap(EditorAccessRow(onLeave: () {})));
      await tester.pumpAndSettle();

      expect(find.text('You can edit this trip'), findsOneWidget);
      expect(find.text('Stop editing this trip'), findsOneWidget);
    });

    testWidgets('Given the exit is tapped, When once, Then onLeave fires exactly once',
        (tester) async {
      var leaves = 0;
      await tester.pumpWidget(_wrap(EditorAccessRow(onLeave: () => leaves++)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop editing this trip'));
      await tester.pumpAndSettle();

      expect(leaves, 1);
    });

    testWidgets('Given a tap on the row body, When outside the button, Then nothing fires',
        (tester) async {
      var leaves = 0;
      await tester.pumpWidget(_wrap(EditorAccessRow(onLeave: () => leaves++)));
      await tester.pumpAndSettle();

      // The card must not be tappable as a whole — the point of this row is
      // that leaving takes a deliberate press on the labelled control.
      await tester.tap(find.text('You can edit this trip'));
      await tester.pumpAndSettle();

      expect(leaves, 0);
    });

    testWidgets('Given a leave in flight, When tapped, Then the action is disabled',
        (tester) async {
      await tester.pumpWidget(_wrap(const EditorAccessRow(onLeave: null)));
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);
    });
  });
}
