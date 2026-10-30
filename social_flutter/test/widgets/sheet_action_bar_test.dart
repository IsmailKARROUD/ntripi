// test/widgets/sheet_action_bar_test.dart
//
// SheetActionBar is what keeps a sheet's buttons on screen — pinned below the
// scroll view by KeyboardSafeSheetBody(actions:), and under the bug reporter's
// list. On its own it owes three things: the sheet's failure message sits above
// the buttons, where the user just tapped; the home indicator replaces the
// bottom gap rather than adding to it; and the buttons line up with the body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

const _screen = Size(400, 800);
const _send = Key('send');

/// The bar at the foot of a bare screen, where a sheet puts it.
Future<void> _pumpBar(
  WidgetTester tester, {
  String? error,
  double? inset,
  double homeIndicator = 0,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(bottom: homeIndicator);
  tester.view.viewPadding = FakeViewPadding(bottom: homeIndicator);
  addTearDown(tester.view.reset);

  final send =
      FilledButton(key: _send, onPressed: () {}, child: const Text('Send'));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildNtripiTheme(),
      home: Material(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: inset == null
              ? SheetActionBar(error: error, child: send)
              : SheetActionBar(error: error, inset: inset, child: send),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'Given no error, When the bar is built, Then it shows its buttons alone',
      (tester) async {
    await _pumpBar(tester);

    expect(find.byKey(_send), findsOneWidget);
    expect(find.byType(SheetErrorRow), findsNothing);
  });

  testWidgets(
      'Given an error, When the bar is built, Then the message sits above the '
      'buttons', (tester) async {
    await _pumpBar(tester, error: 'Internal Server Error');

    final row = find.byType(SheetErrorRow);
    expect(find.descendant(of: row, matching: find.text('Internal Server Error')),
        findsOneWidget);
    expect(tester.getRect(row).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(_send)).top));
  });

  testWidgets(
      'Given no home indicator, When the bar is built, Then 16 px separate the '
      'buttons from the bottom edge', (tester) async {
    await _pumpBar(tester);

    expect(tester.getRect(find.byKey(_send)).bottom, _screen.height - 16);
  });

  testWidgets(
      'Given a home indicator, When the bar is built, Then the indicator '
      'replaces the 16 px gap instead of adding to it', (tester) async {
    await _pumpBar(tester, homeIndicator: 34);

    expect(tester.getRect(find.byKey(_send)).bottom, _screen.height - 34);
  });

  testWidgets(
      'Given the default inset, When the bar is built, Then the buttons sit '
      '16 px from each side', (tester) async {
    await _pumpBar(tester);

    final send = tester.getRect(find.byKey(_send));
    expect(send.left, 16);
    expect(send.right, _screen.width - 16);
  });

  testWidgets(
      'Given a sheet body padded by 20, When the bar gets the same inset, Then '
      'the buttons line up with the body', (tester) async {
    await _pumpBar(tester, inset: 20);

    final send = tester.getRect(find.byKey(_send));
    expect(send.left, 20);
    expect(send.right, _screen.width - 20);
  });

  testWidgets(
      'Given the theme, When the bar is built, Then its top edge is the '
      'nt.border hairline the body scrolls under', (tester) async {
    await _pumpBar(tester);

    final bar = find.byType(SheetActionBar);
    final box = tester.widget<DecoratedBox>(
        find.descendant(of: bar, matching: find.byType(DecoratedBox)).first);
    expect((box.decoration as BoxDecoration).border,
        Border(top: BorderSide(color: tester.element(bar).nt.border)));
  });
}
