// The duration wheel must not silently revert to Cupertino defaults.
//
// CupertinoPicker draws every off-centre row at a hard-coded 44.7% opacity and
// inks its rows with CupertinoColors.label — pure black, resolved against the
// *OS* appearance rather than the app's theme. Over nt.sand that lands near
// 2.9:1, which is what made "Time to spend" unreadable in light mode. These
// tests pin the two properties that fixed it (the rows carry the app's own ink,
// selected and not) and the contract the call sites depend on: Cancel applies
// nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/duration_picker_sheet.dart';

/// Pumps a themed host and returns a context under its Navigator.
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const Text('host');
            },
          ),
        ),
      ),
    ),
  );
  return ctx;
}

TextStyle _styleOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

void main() {
  testWidgets('rows use the app ink, not the Cupertino default', (
    tester,
  ) async {
    final ctx = await _pumpHost(tester);
    showDurationPickerSheet(
      context: ctx,
      title: 'Time to spend',
      days: 0,
      hours: 2,
      minutes: 0,
    );
    await tester.pumpAndSettle();

    final nt = NtripiColors.light;

    final selected = _styleOf(tester, '2 h');
    expect(selected.color, nt.bark);
    expect(selected.fontWeight, FontWeight.w700);

    // The row that CupertinoPicker would have drawn at 44.7% opacity.
    final neighbour = _styleOf(tester, '3 h');
    expect(neighbour.color, nt.text2);
    expect(neighbour.fontWeight, FontWeight.w500);
  });

  testWidgets('Cancel resolves to null and Done to the current parts', (
    tester,
  ) async {
    var ctx = await _pumpHost(tester);
    final cancelled = showDurationPickerSheet(
      context: ctx,
      title: 'Time to spend',
      days: 1,
      hours: 2,
      minutes: 3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await cancelled, isNull);

    ctx = await _pumpHost(tester);
    final done = showDurationPickerSheet(
      context: ctx,
      title: 'Time to spend',
      days: 1,
      hours: 2,
      minutes: 3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(await done, (days: 1, hours: 2, minutes: 3));
  });
}
