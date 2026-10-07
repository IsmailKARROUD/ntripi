// The description editor keeps its caret above the keyboard on the root
// navigator.
//
// Regression: MarkdownEditScreen set `resizeToAvoidBottomInset: false`. Opened
// from the profile tab (the bio) the shell lifted it; opened from itinerary
// detail (the description) it sits on the root navigator, where nothing did —
// the text ran on under the keyboard and the caret with it. One screen, two
// navigators: only once the shell stopped leaking the inset could both callers
// be right with the default.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/markdown_edit_screen.dart';

void main() {
  testWidgets('the caret at the end of a long description is above the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isOnlineProvider.overrideWith((ref) => Stream.value(true))],
        child: MaterialApp(
          theme: buildNtripiTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          }),
        ),
      ),
    );

    // The detail screen's path: a bare push, so no shell lifts anything.
    editMarkdownField(
      ctx,
      initialText: List.filled(30, 'A line of the description').join('\n'),
      title: 'Description',
    );
    await tester.pumpAndSettle();

    // Focus puts the caret at the end, at the bottom of the long text.
    await tester.showKeyboard(find.byType(TextField));
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    final editable =
        tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    final caret = MatrixUtils.transformRect(
      editable.getTransformTo(null),
      editable.getLocalRectForCaret(editable.selection!.extent),
    );
    expect(caret.top, greaterThanOrEqualTo(0));
    expect(caret.bottom, lessThanOrEqualTo(800 - keyboard),
        reason: 'the user must see what they type');
  });
}
