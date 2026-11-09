// test/widgets/expandable_text_test.dart — the one "view more".
//
// A folded text must always offer the rest of itself. The two copies this
// widget replaced measured the overflow without the inherited text style, the
// text scaler or bold text, so under large accessibility text a note rendered
// ellipsised with no link to the rest of it — the last group pins that.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/expandable_text.dart';

const _viewMore = '... view more';
const _viewLess = 'view less';

const _long = 'Take the second car from the front: the exit stairs come up '
    'right at Pyramides, and the walk back along the platform at rush hour '
    'takes longer than the ride. Buy a carnet at the machine, not the desk.';

// 31 characters: two lines at 13 px in a 300 px box (the test font is one em
// per glyph, so about 23 to a line), four or more at twice the size.
const _fitsAtOneX = 'Board at the front of the train';

Widget _host(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  TextStyle? inherited,
}) =>
    MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(
            body: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: 300,
                child: inherited == null
                    ? child
                    : DefaultTextStyle.merge(style: inherited, child: child),
              ),
            ),
          ),
        ),
      ),
    );

/// The folded or unfolded body — the one Text carrying the whole string.
Text _body(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text));

void main() {
  testWidgets('Given a text that fits, Then there is no link', (tester) async {
    await tester.pumpWidget(_host(const ExpandableText('Short note')));
    await tester.pumpAndSettle();

    expect(find.text('Short note'), findsOneWidget);
    expect(find.text(_viewMore), findsNothing);
    expect(find.text(_viewLess), findsNothing);
  });

  testWidgets(
      'Given a text that does not fit, Then it folds to two lines with a link '
      'that unfolds it and folds it back', (tester) async {
    await tester.pumpWidget(_host(const ExpandableText(_long)));
    await tester.pumpAndSettle();

    expect(_body(tester, _long).maxLines, 2);
    expect(find.text(_viewMore), findsOneWidget);

    await tester.tap(find.text(_viewMore));
    await tester.pumpAndSettle();
    expect(_body(tester, _long).maxLines, isNull);
    expect(find.text(_viewLess), findsOneWidget);

    await tester.tap(find.text(_viewLess));
    await tester.pumpAndSettle();
    expect(_body(tester, _long).maxLines, 2);
    expect(find.text(_viewMore), findsOneWidget);
  });

  testWidgets('Given maxLines 1, Then a two-line text already folds',
      (tester) async {
    await tester.pumpWidget(
        _host(const ExpandableText(_fitsAtOneX, maxLines: 1)));
    await tester.pumpAndSettle();

    expect(_body(tester, _fitsAtOneX).maxLines, 1);
    expect(find.text(_viewMore), findsOneWidget);
  });

  group('tapping the folded text', () {
    testWidgets('unfolds it when expandOnTextTap is set', (tester) async {
      await tester.pumpWidget(
          _host(const ExpandableText(_long, expandOnTextTap: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_long));
      await tester.pumpAndSettle();
      expect(find.text(_viewLess), findsOneWidget);
    });

    testWidgets('leaves it to the parent otherwise — a stop card opens its stop',
        (tester) async {
      var parentTaps = 0;
      await tester.pumpWidget(_host(InkWell(
        onTap: () => parentTaps++,
        child: const ExpandableText(_long),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_long));
      await tester.pumpAndSettle();
      expect(parentTaps, 1);
      expect(find.text(_viewMore), findsOneWidget);
    });
  });

  testWidgets('Given an expandedBuilder, Then it renders only the unfolded text',
      (tester) async {
    await tester.pumpWidget(_host(ExpandableText(
      _long,
      expandedBuilder: (context, text) => Text('unfolded: ${text.length}'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('unfolded: ${_long.length}'), findsNothing);

    await tester.tap(find.text(_viewMore));
    await tester.pumpAndSettle();
    expect(find.text('unfolded: ${_long.length}'), findsOneWidget);
    expect(find.text(_long), findsNothing);
  });

  group('a markdown text (foldedText + expandedBuilder)', () {
    Widget formatted(BuildContext context, String text) =>
        Text('formatted: $text');

    testWidgets(
        'Given a text that fits, Then it shows formatted at once, with no '
        'link — its markup is never shown as typed', (tester) async {
      await tester.pumpWidget(_host(ExpandableText(
        '**Short** note',
        foldedText: 'Short note',
        expandedBuilder: formatted,
      )));
      await tester.pumpAndSettle();

      expect(find.text('formatted: **Short** note'), findsOneWidget);
      expect(find.text('**Short** note'), findsNothing);
      expect(find.text(_viewMore), findsNothing);
    });

    testWidgets(
        'Given a text that overflows, Then the fold shows the plain words and '
        'the link opens the formatted text', (tester) async {
      await tester.pumpWidget(_host(ExpandableText(
        '# $_long',
        foldedText: _long,
        expandedBuilder: formatted,
      )));
      await tester.pumpAndSettle();

      expect(_body(tester, _long).maxLines, 2);
      expect(find.text('# $_long'), findsNothing);

      await tester.tap(find.text(_viewMore));
      await tester.pumpAndSettle();
      expect(find.text('formatted: # $_long'), findsOneWidget);
    });

    testWidgets(
        'Given the plain words fit though the source would not, Then the fold '
        'measures the plain words — markup is not length', (tester) async {
      // 31 visible characters fit two lines; the link's address would not.
      const source = '[$_fitsAtOneX](https://example.com/a/very/long/path/'
          'that/would/wrap/onto/more/lines)';
      await tester.pumpWidget(_host(ExpandableText(
        source,
        foldedText: _fitsAtOneX,
        expandedBuilder: formatted,
      )));
      await tester.pumpAndSettle();

      expect(find.text(_viewMore), findsNothing);
      expect(find.text('formatted: $source'), findsOneWidget);
    });

    testWidgets(
        'Given a short formatted text inside something with a tap of its own, '
        'Then the tap still reaches it', (tester) async {
      var parentTaps = 0;
      await tester.pumpWidget(_host(InkWell(
        onTap: () => parentTaps++,
        child: ExpandableText(
          'Short',
          foldedText: 'Short',
          // A builder that would take every tap — as selectable markdown does.
          expandedBuilder: (context, text) =>
              GestureDetector(onTap: () {}, child: Text('formatted: $text')),
        ),
      )));
      await tester.pumpAndSettle();

      // The text itself is not hit: that is the point.
      await tester.tap(find.text('formatted: Short'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(parentTaps, 1);
    });
  });

  testWidgets('Given the link, Then a screen reader hears a button',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const ExpandableText(_long)));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text(_viewMore)),
      matchesSemantics(
        label: _viewMore,
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  // Regression: measured with less than Text renders with, the check said
  // "fits" while the Text ellipsised — and the rest of the note was unreachable.
  group('the overflow is measured as the text is rendered', () {
    testWidgets('Given it fits at 1x, Then it shows whole with no link',
        (tester) async {
      await tester.pumpWidget(_host(const ExpandableText(_fitsAtOneX)));
      await tester.pumpAndSettle();

      expect(find.text(_viewMore), findsNothing);
    });

    testWidgets(
        'Given large accessibility text, When the same text no longer fits, '
        'Then the link is offered', (tester) async {
      await tester.pumpWidget(_host(
        const ExpandableText(_fitsAtOneX),
        textScaler: const TextScaler.linear(2),
      ));
      await tester.pumpAndSettle();

      expect(find.text(_viewMore), findsOneWidget);
    });

    testWidgets(
        'Given an inherited style that widens the text, When it no longer '
        'fits, Then the link is offered', (tester) async {
      await tester.pumpWidget(_host(
        const ExpandableText(_fitsAtOneX),
        inherited: const TextStyle(letterSpacing: 12),
      ));
      await tester.pumpAndSettle();

      expect(find.text(_viewMore), findsOneWidget);
    });
  });
}
