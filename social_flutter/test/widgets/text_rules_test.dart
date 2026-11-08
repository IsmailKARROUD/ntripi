// The text rules a field is held to before Save (shared/widgets/text_rules.dart):
// the server's own refusal (422 text_contains_link) said under the field as
// the user types, Save off while it lasts, and an untouched old link never in
// the way — the server refuses a link only in a text that changed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/markdown_edit_screen.dart';
import 'package:ntripi/shared/widgets/text_rules.dart';

void main() {
  group('textRuleBreak', () {
    test('Given a new text with a link, Then it names the exact link', () {
      final breach = textRuleBreak('Book on booking.com.', TextRules.userText);
      expect(breach, isA<LinkInText>());
      expect((breach! as LinkInText).match, 'booking.com');
    });

    test(
        'Given a link already stored, When the text is unchanged (blanks '
        'aside), Then nothing breaks', () {
      const old = 'Booked on booking.com';
      expect(textRuleBreak(old, TextRules.userText, initial: old), isNull);
      expect(textRuleBreak('$old  ', TextRules.userText, initial: old), isNull);
    });

    test('Given an edit to a text holding an old link, Then the link counts',
        () {
      expect(
        textRuleBreak('Booked on booking.com, twice', TextRules.userText,
            initial: 'Booked on booking.com'),
        isA<LinkInText>(),
      );
    });

    test('Given rules that allow links, Then a link is fine', () {
      expect(
          textRuleBreak('www.x.com', const TextRules(refuseLinks: false)),
          isNull);
    });
  });

  group('a form held to the rules (the description editor)', () {
    Future<AppLocalizations> pumpEditor(
        WidgetTester tester, String initialText) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [isOnlineProvider.overrideWith((ref) => Stream.value(true))],
        child: MaterialApp(
          theme: buildNtripiTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarkdownEditScreen(
              initialText: initialText, title: 'Description'),
        ),
      ));
      await tester.pumpAndSettle();
      return AppLocalizations.of(
          tester.element(find.byType(MarkdownEditScreen)))!;
    }

    TextButton save(WidgetTester tester, AppLocalizations l10n) =>
        tester.widget<TextButton>(
            find.widgetWithText(TextButton, l10n.save));

    testWidgets(
        'Given a link typed in, Then the field names it and Save is off, and '
        'removing it turns Save back on', (tester) async {
      final l10n = await pumpEditor(tester, '');

      await tester.enterText(find.byType(TextField), 'Tickets: www.example.com');
      await tester.pumpAndSettle();
      expect(find.text(l10n.textRuleNoLinks('www.example.com')), findsOneWidget);
      expect(save(tester, l10n).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Tickets at the door');
      await tester.pumpAndSettle();
      expect(find.text(l10n.textRuleNoLinks('www.example.com')), findsNothing);
      expect(save(tester, l10n).onPressed, isNotNull);
    });

    testWidgets(
        'Given a description saved before the rule, with a link, When it '
        'opens untouched, Then nothing is said and Save is on', (tester) async {
      final l10n = await pumpEditor(tester, 'Booked on booking.com');

      expect(find.textContaining('booking.com', findRichText: true),
          findsWidgets);
      expect(find.text(l10n.textRuleNoLinks('booking.com')), findsNothing);
      expect(save(tester, l10n).onPressed, isNotNull);
    });
  });
}
