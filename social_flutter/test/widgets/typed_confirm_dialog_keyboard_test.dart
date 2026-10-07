// The type-to-confirm dialog scrolls rather than overflow under the keyboard.
//
// Regression: its content was a fixed Column with the autofocused field last.
// A dialog already shrinks above the keyboard, so on a short phone (or with
// large text) a long warning pushed the field out of the dialog — overflowing
// exactly the control the user had to type into to delete their account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

void main() {
  testWidgets('a long warning on a short phone keeps the field above the '
      'keyboard', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ),
    );

    const keyboard = 260.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    confirmTypedDestructiveAction(
      context: ctx,
      title: 'Delete account',
      message: List.filled(
        10,
        'Deleting removes every itinerary, stop, note and rating for good.',
      ).join(' '),
      requiredText: 'DELETE',
    );
    // An overflow would throw here and fail the test on its own.
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(667 - keyboard),
        reason: 'the autofocused field must be visible to type into');
  });
}
