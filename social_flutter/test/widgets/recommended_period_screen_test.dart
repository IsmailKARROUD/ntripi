// test/widgets/recommended_period_screen_test.dart
//
// Two guards on the period editor, both of which lose the user's work silently
// if broken:
//
//  1. Backing out with unsaved edits must ask first. The screen pops its value
//     rather than saving, so an unguarded back press discards everything with
//     no undo and no trace.
//  2. Clear wipes months, exact days, weekdays and the note in one tap, so it
//     asks too — and is disabled outright when there is nothing to clear.
//
// Also pinned: the guard is by VALUE, so toggling a month on and back off again
// is not "unsaved changes" and must not nag on the way out.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/confirm_dialog.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';
import 'package:social_flutter/features/itineraries/presentation/recommended_period_screen.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  /// Pushes the screen onto a host route so a real back navigation can be
  /// driven, and records what it popped with.
  Future<void> pumpScreen(
    WidgetTester tester, {
    RecommendedPeriod? initial,
    required List<RecommendedPeriod?> popped,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped.add(
                    await Navigator.push<RecommendedPeriod>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RecommendedPeriodScreen(initial: initial),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  }

  group('unsaved-changes guard', () {
    testWidgets('Given no edits, When backing out, Then it leaves immediately',
        (tester) async {
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tapBack(tester);

      expect(find.text(en.discardChangesTitle), findsNothing);
      expect(popped, [null]);
    });

    testWidgets('Given a month was picked, When backing out, Then it confirms',
        (tester) async {
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      await tapBack(tester);

      expect(find.text(en.discardChangesTitle), findsOneWidget);
      // Still on the editor until the user answers.
      expect(popped, isEmpty);
    });

    testWidgets('Given the confirm is dismissed, Then the edits survive',
        (tester) async {
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      await tapBack(tester);
      await tester.tap(find.text(en.keepEditingButton));
      await tester.pumpAndSettle();

      expect(popped, isEmpty);
      expect(find.text('June'), findsOneWidget); // the derived window row
    });

    testWidgets('Given discard is confirmed, Then it pops with null',
        (tester) async {
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      await tapBack(tester);
      await tester.tap(find.text(en.discardButton));
      await tester.pumpAndSettle();

      // null, not an empty period — the caller reads that as "left untouched".
      expect(popped, [null]);
    });

    testWidgets(
        'Given a month toggled on then off, When backing out, Then no prompt',
        (tester) async {
      // The guard compares by value, not by "did anything get tapped".
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      await tapBack(tester);

      expect(find.text(en.discardChangesTitle), findsNothing);
      expect(popped, [null]);
    });

    testWidgets('Given typing in the note, When backing out, Then it confirms',
        (tester) async {
      // The note has no setState of its own — a controller listener is what
      // keeps canPop fresh, and this is the test that it is wired up.
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tester.enterText(find.byType(TextField), 'fewer crowds');
      await tester.pumpAndSettle();
      await tapBack(tester);

      expect(find.text(en.discardChangesTitle), findsOneWidget);
    });

    testWidgets('Given edits, When Done is tapped, Then it saves without asking',
        (tester) async {
      // Done pops imperatively, which bypasses PopScope — the guard must not
      // intercept the save path.
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, popped: popped);

      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.done));
      await tester.pumpAndSettle();

      expect(find.text(en.discardChangesTitle), findsNothing);
      expect(popped.single?.windows,
          [const PeriodWindow(fromMonth: 6, toMonth: 6)]);
    });
  });

  group('clear', () {
    const seeded = RecommendedPeriod(
      windows: [PeriodWindow(fromMonth: 4, toMonth: 6)],
      weekdays: [6, 7],
      note: 'blossom',
    );

    testWidgets('Given nothing is set, Then the clear button is disabled',
        (tester) async {
      await pumpScreen(tester, popped: <RecommendedPeriod?>[]);

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, en.periodClear),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Given a period is set, When Clear is tapped, Then it confirms',
        (tester) async {
      await pumpScreen(tester,
          initial: seeded, popped: <RecommendedPeriod?>[]);

      await tester.tap(find.widgetWithText(TextButton, en.periodClear));
      await tester.pumpAndSettle();

      expect(find.text(en.periodClearConfirmTitle), findsOneWidget);
    });

    testWidgets('Given the clear confirm is cancelled, Then nothing is lost',
        (tester) async {
      await pumpScreen(tester,
          initial: seeded, popped: <RecommendedPeriod?>[]);

      await tester.tap(find.widgetWithText(TextButton, en.periodClear));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();

      expect(find.text('blossom'), findsOneWidget);
      expect(find.text('April – June'), findsOneWidget);
    });

    testWidgets('Given clear is confirmed, Then every part is wiped',
        (tester) async {
      final popped = <RecommendedPeriod?>[];
      await pumpScreen(tester, initial: seeded, popped: popped);

      await tester.tap(find.widgetWithText(TextButton, en.periodClear));
      await tester.pumpAndSettle();
      // The confirm label is the same word as the button that opened it, so
      // scope the finder to the dialog's own subtree.
      await tester.tap(find.descendant(
        of: find.byType(ConfirmDialog),
        matching: find.text(en.periodClear),
      ));
      await tester.pumpAndSettle();

      expect(find.text('blossom'), findsNothing);
      expect(find.text(en.periodNoMonthsSelected), findsOneWidget);

      await tester.tap(find.text(en.done));
      await tester.pumpAndSettle();
      expect(popped.single?.isEmpty, isTrue);
    });
  });
}
