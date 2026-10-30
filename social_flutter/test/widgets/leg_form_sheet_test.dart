// test/widgets/leg_form_sheet_test.dart
//
// The transport-leg sheet's buttons are pinned below its body (SheetActionBar).
// As the body's last child they sat under the keyboard while the thoughts — the
// last field — were typed.
//
// Each button keeps its contract with the caller, documented at the top of
// leg_form_dialog.dart: Save pops the leg, Delete pops the delete sentinel, and
// Cancel pops nothing — asking first when there is something to lose, exactly
// as dragging the sheet down does.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/domain/transport_leg.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

TransportLeg _busLeg() => TransportLeg(
      id: 'leg-1',
      segmentId: 'seg-1',
      position: 0,
      mode: TransportMode.bus,
      line: '42',
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  /// Opens the sheet over a host page and records what it popped with.
  Future<void> openSheet(
    WidgetTester tester, {
    TransportLeg? existing,
    required List<Map<String, dynamic>?> popped,
    Size size = const Size(1000, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNtripiTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => popped
                      .add(await LegFormDialog.show(context, existing: existing)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder thoughts() => find.widgetWithText(TextField, en.legThoughtsLabel);
  Finder cancel() => find.widgetWithText(TextButton, en.cancel);

  testWidgets(
      'Given a short phone, When the thoughts are typed with the keyboard up, '
      'Then Add Transit stays on screen above the keyboard', (tester) async {
    await openSheet(tester, popped: [], size: const Size(375, 667));

    await tester.showKeyboard(thoughts());
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, en.addTransitTitle);
    expect(save.hitTestable(), findsOneWidget);
    final saveRect = tester.getRect(save);
    expect(saveRect.bottom, lessThanOrEqualTo(667 - 260));
    expect(tester.getRect(thoughts()).bottom, lessThanOrEqualTo(saveRect.top),
        reason: 'the field is revealed above the bar, not behind it');
  });

  testWidgets(
      'Given a new leg, When Add Transit is tapped, Then the sheet pops the leg '
      'and offered no Delete', (tester) async {
    final popped = <Map<String, dynamic>?>[];
    await openSheet(tester, popped: popped);
    expect(find.widgetWithText(TextButton, en.deleteButton), findsNothing);

    await tester.enterText(thoughts(), '  Take the coast path  ');
    await tester.tap(find.widgetWithText(FilledButton, en.addTransitTitle));
    await tester.pumpAndSettle();

    expect(popped, [
      {'mode': 'walk', 'notes': 'Take the coast path', 'is_free': false},
    ]);
  });

  testWidgets(
      'Given an existing leg, When Update Transit is tapped, Then the sheet '
      'pops the leg as edited', (tester) async {
    final popped = <Map<String, dynamic>?>[];
    await openSheet(tester, existing: _busLeg(), popped: popped);

    await tester.enterText(find.widgetWithText(TextField, '42'), '43');
    await tester.tap(find.widgetWithText(FilledButton, en.updateTransitButton));
    await tester.pumpAndSettle();

    expect(popped, [
      {'mode': 'bus', 'line': '43', 'is_free': false},
    ]);
  });

  testWidgets(
      'Given an existing leg, When Delete is tapped, Then the sheet pops the '
      'delete sentinel', (tester) async {
    final popped = <Map<String, dynamic>?>[];
    await openSheet(tester, existing: _busLeg(), popped: popped);

    final delete = find.widgetWithText(TextButton, en.deleteButton);
    expect(find.descendant(of: find.byType(SheetActionBar), matching: delete),
        findsOneWidget);
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(popped, [
      {'__action': 'delete'},
    ]);
  });

  testWidgets(
      'Given no changes, When Cancel is tapped, Then the sheet closes with no '
      'leg and without asking', (tester) async {
    final popped = <Map<String, dynamic>?>[];
    await openSheet(tester, popped: popped);

    await tester.tap(cancel());
    await tester.pumpAndSettle();

    expect(find.text(en.discardChangesTitle), findsNothing);
    expect(popped, [null]);
  });

  testWidgets(
      'Given typed thoughts, When Cancel is tapped and Keep editing chosen, '
      'Then the sheet stays open with the text', (tester) async {
    final popped = <Map<String, dynamic>?>[];
    await openSheet(tester, popped: popped);
    await tester.enterText(thoughts(), 'Take the coast path');

    await tester.tap(cancel());
    await tester.pumpAndSettle();
    expect(find.text(en.discardChangesTitle), findsOneWidget);

    await tester.tap(find.text(en.keepEditingButton));
    await tester.pumpAndSettle();

    expect(popped, isEmpty);
    expect(find.text('Take the coast path'), findsOneWidget);
  });

  testWidgets(
      'Given typed thoughts, When Cancel is tapped and Discard confirmed, '
      'Then the sheet closes with no leg', (tester) async {
    final popped = <Map<String, dynamic>?>[];
    await openSheet(tester, popped: popped);
    await tester.enterText(thoughts(), 'Take the coast path');

    await tester.tap(cancel());
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.discardButton));
    await tester.pumpAndSettle();

    expect(popped, [null]);
  });
}
