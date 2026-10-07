// The keyboard-avoidance primitives, on their own.
//
// RevealTogether widens a field's "show my caret" request to the whole group —
// the box, its counter, the hint under it — when the group fits, and stands
// aside when it does not, so a long note never loses its caret.
// KeyboardSafeSheetBody lifts a sheet's body with the inset OUTSIDE its scroll
// view: the old pattern (inset padding inside it) was cancelled by the sheets'
// 0.7 height cap, which left the last field under the keyboard, counted as
// visible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/shared/widgets/keyboard_avoidance.dart';

const _keyboard = 300.0;
const _keyboardTop = 800 - _keyboard;

void _phone(WidgetTester tester, {Size size = const Size(400, 800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A page whose [group] starts on screen and is under the keyboard once it
/// rises — the annotation and stop-notes situation.
Widget _page(Widget group) => MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [const SizedBox(height: 520), group, const SizedBox(height: 400)],
        ),
      ),
    );

Future<void> _raiseKeyboard(WidgetTester tester, {double height = _keyboard}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  await tester.pumpAndSettle();
}

Rect _caretRect(WidgetTester tester) {
  final editable =
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
  final local = editable.getLocalRectForCaret(editable.selection!.extent);
  return MatrixUtils.transformRect(editable.getTransformTo(null), local);
}

void main() {
  group('RevealTogether', () {
    testWidgets('lifts the field and the hint under it as one unit',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_page(RevealTogether(
        child: Column(children: const [
          TextField(key: Key('field'), minLines: 3, maxLines: 3),
          SizedBox(key: Key('hint'), height: 120),
        ]),
      )));

      await tester.showKeyboard(find.byKey(const Key('field')));
      await _raiseKeyboard(tester);

      expect(tester.getRect(find.byKey(const Key('hint'))).bottom,
          lessThanOrEqualTo(_keyboardTop));
    });

    testWidgets('without it only the caret line rises (the control)',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_page(Column(children: const [
        TextField(key: Key('field'), minLines: 3, maxLines: 3),
        SizedBox(key: Key('hint'), height: 120),
      ])));

      await tester.showKeyboard(find.byKey(const Key('field')));
      await _raiseKeyboard(tester);

      expect(_caretRect(tester).bottom, lessThanOrEqualTo(_keyboardTop));
      expect(tester.getRect(find.byKey(const Key('hint'))).bottom,
          greaterThan(_keyboardTop),
          reason: 'a bare field reveals its caret line, not what is under it');
    });

    testWidgets('a group taller than the viewport keeps the caret in view',
        (tester) async {
      _phone(tester);
      final controller =
          TextEditingController(text: List.filled(40, 'line').join('\n'));
      addTearDown(controller.dispose);
      await tester.pumpWidget(_page(RevealTogether(
        child: Column(children: [
          TextField(controller: controller, maxLines: null),
          const SizedBox(height: 120),
        ]),
      )));

      // Focus lands the caret at the end of the 40 lines, far below the group's
      // top: revealing the group by its leading edge would push it off screen.
      await tester.showKeyboard(find.byType(TextField));
      await _raiseKeyboard(tester);

      final caret = _caretRect(tester);
      expect(caret.top, greaterThanOrEqualTo(0));
      expect(caret.bottom, lessThanOrEqualTo(_keyboardTop));
    });

    testWidgets('nested groups compose: the outer one wins when it fits',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_page(RevealTogether(
        child: Column(children: [
          RevealTogether(
            child: Column(children: const [
              TextField(key: Key('field'), minLines: 2, maxLines: 2),
              SizedBox(height: 40),
            ]),
          ),
          const SizedBox(key: Key('outerHint'), height: 80),
        ]),
      )));

      await tester.showKeyboard(find.byKey(const Key('field')));
      await _raiseKeyboard(tester);

      expect(tester.getRect(find.byKey(const Key('outerHint'))).bottom,
          lessThanOrEqualTo(_keyboardTop));
    });
  });

  group('KeyboardSafeSheetBody', () {
    late BuildContext ctx;
    Widget host() => MaterialApp(
          home: Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          }),
        );

    testWidgets('the last field of a capped sheet reveals itself above the '
        'keyboard, without overflowing a short phone', (tester) async {
      _phone(tester, size: const Size(375, 667));
      await tester.pumpWidget(host());

      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => KeyboardSafeSheetBody(
          child: Column(children: const [
            SizedBox(height: 600), // taller than the 70 % cap on its own
            TextField(key: Key('last'), minLines: 2, maxLines: 2),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.showKeyboard(find.byKey(const Key('last')));
      await _raiseKeyboard(tester, height: 260);

      expect(tester.getRect(find.byKey(const Key('last'))).bottom,
          lessThanOrEqualTo(667 - 260));
    });

    testWidgets('consumes the inset: nothing inside it sees the keyboard',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(host());
      await _raiseKeyboard(tester);

      double? seen;
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => KeyboardSafeSheetBody(
          child: Builder(builder: (c) {
            seen = MediaQuery.viewInsetsOf(c).bottom;
            return const SizedBox(height: 100);
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(seen, 0, reason: 'a nested reader must not lift a second time');
    });
  });
}
