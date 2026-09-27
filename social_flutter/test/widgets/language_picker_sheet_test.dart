// The language sheet must hold a fixed frame, whatever the keyboard does.
//
// Regression: the sheet sized itself to its content, and a modal bottom sheet
// is anchored to the bottom of the window — so raising the keyboard (which
// pads the list) or typing a query that narrows it to a couple of rows walked
// the sheet's top edge, and the Done button with it, up and down the screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/profile/presentation/language_picker_sheet.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/languages.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

Rect _sheetRect(WidgetTester tester) => tester.getRect(
      find
          .ancestor(
            of: find.byType(ListView),
            matching: find.byType(Material),
          )
          .first,
    );

void main() {
  testWidgets('sheet keeps a fixed 50% frame across keyboard and filtering',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    showLanguagePickerSheet(ctx);
    await tester.pumpAndSettle();

    const expected = Rect.fromLTRB(0, 400, 400, 800); // 50% of an 800pt screen
    expect(_sheetRect(tester), expected);

    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();
    expect(_sheetRect(tester), expected, reason: 'keyboard must not move it');

    // A query narrowing the list to a row or two must not shrink the frame.
    await tester.enterText(find.byType(TextField), 'zulu');
    await tester.pumpAndSettle();
    expect(_sheetRect(tester), expected, reason: 'filtering must not move it');
  });

  testWidgets('the language cap is announced inside the sheet', (tester) async {
    // It used to be a snackbar, which draws behind the modal barrier: a tap past
    // the cap simply did nothing, with no visible reason why.
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    final atCap = kLanguages.take(60).map((l) => l.code).toList();
    final extra = kLanguages[60];
    showLanguagePickerSheet(ctx, selected: atCap);
    await tester.pumpAndSettle();
    expect(find.byType(SheetErrorRow), findsNothing);

    await tester.enterText(find.byType(TextField), extra.name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, extra.name).first);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(ctx)!;
    expect(find.byType(SheetErrorRow), findsOneWidget);
    expect(find.text(l10n.maxLanguagesReached(60)), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
