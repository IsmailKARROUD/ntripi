// The annotation message box — and the hint under it — must rise above the
// keyboard.
//
// Regression: the screen set `resizeToAvoidBottomInset: false`, compensating
// for the shell handing its tabs the keyboard inset twice. But every caller
// pushes it on the root navigator, outside the shell, so nothing resized: the
// list ran on under the keyboard, the field believed it was on screen, and the
// user typed blind. The hint assertion pins RevealTogether: a field on its own
// reveals only its caret line.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/presentation/annotation_screen.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

void main() {
  testWidgets('message field and its hint sit above the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isOnlineProvider.overrideWith((_) => Stream.value(true))],
        child: MaterialApp(
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
      ),
    );

    // The stop card makes the content taller, as on the stop-level path.
    showAnnotationScreen(ctx, stopName: 'Jemaa el-Fnaa', stopSubtitle: 'Marrakesh');
    await tester.pumpAndSettle();

    // Autofocus has already focused the field; now the keyboard arrives.
    const keyboard = 346.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    const keyboardTop = 932 - keyboard;
    final l10n = AppLocalizations.of(tester.element(find.byType(AnnotationScreen)))!;
    expect(tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: 'the message box must scroll up above the keyboard');
    expect(tester.getRect(find.text(l10n.annotationKeepShortHint)).bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: 'the hint under the box should come into view with it');
  });
}
