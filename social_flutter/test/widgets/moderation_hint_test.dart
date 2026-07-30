// test/widgets/moderation_hint_test.dart
//
// ModerationHint is advisory by contract: it may show a line of text and it may
// do nothing at all, but it can never interfere with what the user is writing.
// These tests pin that contract down — especially the failure path, since a
// checker that throws must read as "clean" rather than take the form with it.
//
// The real wordlist can't initialise under `flutter test` (and correctly
// degrades to clean when it fails), so every case injects a fake checker.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/moderation_hint.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  // Longer than the widget's 600 ms debounce, so one pump settles a check.
  const pastDebounce = Duration(milliseconds: 800);

  Future<void> pumpHint(
    WidgetTester tester,
    Future<bool> Function(String) checker,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ModerationHint(
            controller: controller,
            checker: checker,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );
  }

  // Flagged text is judged by the fake, so the assertion is about the widget's
  // reaction, not about any particular word being offensive.
  Future<bool> flagsEverything(String text) async => text.trim().isNotEmpty;
  Future<bool> flagsNothing(String text) async => false;

  String hintTitle(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TextField)))!
          .moderationHintTitle;

  testWidgets('shows the hint once the writer pauses on flagged text',
      (tester) async {
    await pumpHint(tester, flagsEverything);
    expect(find.text(hintTitle(tester)), findsNothing);

    await tester.enterText(find.byType(TextField), 'something rude');
    // Still nothing mid-typing: the hint waits for the debounce.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(hintTitle(tester)), findsNothing);

    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(find.text(hintTitle(tester)), findsOneWidget);
  });

  testWidgets('never blocks or mutates the field it wraps', (tester) async {
    await pumpHint(tester, flagsEverything);
    await tester.enterText(find.byType(TextField), 'something rude');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text(hintTitle(tester)), findsOneWidget);

    // The text is untouched and the field is still editable while flagged.
    expect(controller.text, 'something rude');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isNot(false));
    expect(field.readOnly, isFalse);

    await tester.enterText(find.byType(TextField), 'something rude and more');
    expect(controller.text, 'something rude and more');
  });

  testWidgets('a checker that throws degrades to clean', (tester) async {
    await pumpHint(tester, (_) async => throw Exception('wordlist unavailable'));
    await tester.enterText(find.byType(TextField), 'anything at all');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(hintTitle(tester)), findsNothing);
    expect(controller.text, 'anything at all');
  });

  testWidgets('hint disappears once the text is cleaned up', (tester) async {
    // Flags only while the offending word is present, so the same widget can
    // go flagged → clean the way an edit would.
    await pumpHint(tester, (text) async => text.contains('rude'));

    await tester.enterText(find.byType(TextField), 'something rude');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(find.text(hintTitle(tester)), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'something polite');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(find.text(hintTitle(tester)), findsNothing);
  });

  testWidgets('clean text never shows a hint', (tester) async {
    await pumpHint(tester, flagsNothing);
    await tester.enterText(find.byType(TextField), 'a lovely walk by the sea');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text(hintTitle(tester)), findsNothing);
  });
}
