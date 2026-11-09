// The text rules a field is held to before Save (shared/widgets/text_rules.dart):
// the server's own refusals — a link (422 text_contains_link) and a text over
// its field's cap (422 string_too_long) — said under the field as the user
// types, Save off while either lasts. An untouched old link is never in the
// way (the server refuses a link only in a text that changed), the count shows
// from 90% of the cap, and nothing typed or pasted is ever cut.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/text/text_limits.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/markdown_edit_screen.dart';
import 'package:ntripi/shared/widgets/text_rules.dart';

const _rules = TextRules(TextLimits.itineraryDescription);

void main() {
  group('textRuleBreak — links', () {
    test('Given a new text with a link, Then it names the exact link', () {
      final breach = textRuleBreak('Book on booking.com.', _rules);
      expect(breach, isA<LinkInText>());
      expect((breach! as LinkInText).match, 'booking.com');
    });

    test(
        'Given a link already stored, When the text is unchanged (blanks '
        'aside), Then nothing breaks', () {
      const old = 'Booked on booking.com';
      expect(textRuleBreak(old, _rules, initial: old), isNull);
      expect(textRuleBreak('$old  ', _rules, initial: old), isNull);
    });

    test('Given an edit to a text holding an old link, Then the link counts',
        () {
      expect(
        textRuleBreak('Booked on booking.com, twice', _rules,
            initial: 'Booked on booking.com'),
        isA<LinkInText>(),
      );
    });

    test('Given rules that allow links, Then a link is fine', () {
      expect(
          textRuleBreak('www.x.com',
              const TextRules(TextLimits.reportNotes, refuseLinks: false)),
          isNull);
    });
  });

  group('textRuleBreak — the cap', () {
    test('Given a text at its cap, Then nothing breaks; one more, Then it does',
        () {
      const rules = TextRules(10);
      expect(textRuleBreak('a' * 10, rules), isNull);
      final breach = textRuleBreak('a' * 11, rules);
      expect(breach, isA<TextTooLong>());
      expect((breach! as TextTooLong).limit, 10);
    });

    test(
        'Given blanks around the text, Then they do not count — every form '
        'sends it trimmed', () {
      expect(textRuleBreak('  ${'a' * 10}\n\n', const TextRules(10)), isNull);
    });

    test(
        'Given emoji, Then each counts once, as the server counts code points '
        '(Dart\'s length would count two)', () {
      final tenEmoji = '🌍' * 10;
      expect(tenEmoji.length, 20);
      expect(textLength(tenEmoji), 10);
      expect(textRuleBreak(tenEmoji, const TextRules(10)), isNull);
    });

    test('Given a stored text over the cap, Then it still breaks — a field is '
        'sent whole', () {
      final long = 'a' * 11;
      expect(textRuleBreak(long, const TextRules(10), initial: long),
          isA<TextTooLong>());
    });

    test('Given both a link and too much text, Then the link is named first',
        () {
      expect(textRuleBreak('see x.com ${'a' * 20}', const TextRules(10)),
          isA<LinkInText>());
    });
  });

  group('TextRulesNote — the count', () {
    Future<void> pumpNote(WidgetTester tester, TextEditingController c,
        {int limit = 100}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TextRulesNote(RuledField(c, rules: TextRules(limit))),
        ),
      ));
    }

    testWidgets('Given a text under 90% of its cap, Then nothing shows',
        (tester) async {
      final c = TextEditingController(text: 'a' * 89);
      addTearDown(c.dispose);
      await pumpNote(tester, c);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets(
        'Given 90% of the cap, Then the count shows quietly, with no message',
        (tester) async {
      final c = TextEditingController(text: 'a' * 90);
      addTearDown(c.dispose);
      await pumpNote(tester, c);

      final count = tester.widget<Text>(find.text('90/100'));
      expect(count.style!.color, NtripiColors.light.text3);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets(
        'Given a text past the cap, Then the count turns red and the message '
        'says the cap', (tester) async {
      final c = TextEditingController(text: 'a' * 90);
      addTearDown(c.dispose);
      await pumpNote(tester, c);
      final l10n =
          AppLocalizations.of(tester.element(find.byType(TextRulesNote)))!;

      c.text = 'a' * 101;
      await tester.pump();

      final count = tester.widget<Text>(find.text('101/100'));
      expect(count.style!.color, NtripiColors.light.danger);
      expect(find.text(l10n.textRuleTooLong(100)), findsOneWidget);
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
              initialText: initialText, title: 'Description', rules: _rules),
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

    testWidgets(
        'Given a paste past the 10,000-character cap, Then nothing is cut, the '
        'count is red and Save is off until the text is back under it',
        (tester) async {
      final l10n = await pumpEditor(tester, '');
      final over = 'Long road. ' * 910; // 10,010 characters, trimmed 10,009

      await tester.enterText(find.byType(TextField), over);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, over, reason: 'never cut');
      expect(field.maxLength, isNull);
      expect(find.text('${textLength(over)}/10000'), findsOneWidget);
      expect(find.text(l10n.textRuleTooLong(10000)), findsOneWidget);
      expect(save(tester, l10n).onPressed, isNull);

      await tester.enterText(find.byType(TextField), over.substring(0, 9990));
      await tester.pumpAndSettle();
      expect(find.text(l10n.textRuleTooLong(10000)), findsNothing);
      expect(save(tester, l10n).onPressed, isNotNull);
    });
  });
}
