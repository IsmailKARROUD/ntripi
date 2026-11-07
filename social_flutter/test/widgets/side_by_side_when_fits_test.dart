// test/widgets/side_by_side_when_fits_test.dart — "in one row, unless there is
// no room": two pieces sit side by side when both fit at their natural widths,
// and stack as on a phone, each as wide as the box, when they do not.
//
// The answer comes from the children's own measurements at every layout — the
// text scale included — so a resize or a bigger text setting moves between
// the two without rebuilding either piece.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/shared/widgets/side_by_side_when_fits.dart';

const _start = Key('start');
const _end = Key('end');

/// A start piece 200 × 40 and an end piece 100 × 20: together, with the
/// default 16 px between them, 316 px wide.
Widget _boxes({
  required double width,
  TextDirection direction = TextDirection.ltr,
  CrossAxisAlignment cross = CrossAxisAlignment.center,
  Widget? end,
}) =>
    Directionality(
      textDirection: direction,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: width,
          child: SideBySideWhenFits(
            crossAxisAlignment: cross,
            start: const SizedBox(key: _start, width: 200, height: 40),
            end: end ?? const SizedBox(key: _end, width: 100, height: 20),
          ),
        ),
      ),
    );

bool _sideBySide(WidgetTester tester) => tester
    .renderObject<RenderSideBySideWhenFits>(find.byType(SideBySideWhenFits))
    .sideBySide;

/// Counts how often it is built from scratch.
class _Kept extends StatefulWidget {
  const _Kept();

  static int inits = 0;

  @override
  State<_Kept> createState() => _KeptState();
}

class _KeptState extends State<_Kept> {
  @override
  void initState() {
    super.initState();
    _Kept.inits++;
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: _end, width: 100, height: 20);
}

void main() {
  testWidgets(
      'Given room for both, Then they share a row: the start piece at the '
      'start edge, the end piece at the end edge, the shorter one centred',
      (tester) async {
    await tester.pumpWidget(_boxes(width: 400));

    expect(_sideBySide(tester), isTrue);
    expect(tester.getRect(find.byKey(_start)),
        const Rect.fromLTWH(0, 0, 200, 40));
    expect(tester.getRect(find.byKey(_end)),
        const Rect.fromLTWH(300, 10, 100, 20));
    expect(tester.getSize(find.byType(SideBySideWhenFits)),
        const Size(400, 40));
  });

  testWidgets(
      'Given exactly the room both need, Then they still share the row; one '
      'pixel less, Then they stack', (tester) async {
    await tester.pumpWidget(_boxes(width: 316));
    expect(_sideBySide(tester), isTrue);

    await tester.pumpWidget(_boxes(width: 315));
    expect(_sideBySide(tester), isFalse);
  });

  testWidgets(
      'Given no room, Then the start piece sits above the end piece, each as '
      'wide as the box — the phone layout', (tester) async {
    await tester.pumpWidget(_boxes(width: 300));

    expect(tester.getRect(find.byKey(_start)),
        const Rect.fromLTWH(0, 0, 300, 40));
    expect(tester.getRect(find.byKey(_end)),
        const Rect.fromLTWH(0, 40, 300, 20));
    expect(tester.getSize(find.byType(SideBySideWhenFits)),
        const Size(300, 60));
  });

  testWidgets('Given right-to-left, Then the start piece is on the right',
      (tester) async {
    await tester.pumpWidget(_boxes(width: 400, direction: TextDirection.rtl));

    final box = tester.getRect(find.byType(SideBySideWhenFits));
    expect(tester.getRect(find.byKey(_start)),
        Rect.fromLTWH(box.right - 200, 0, 200, 40));
    expect(tester.getRect(find.byKey(_end)),
        Rect.fromLTWH(box.left, 10, 100, 20));
  });

  testWidgets('Given end alignment, Then the shorter piece sits on the bottom',
      (tester) async {
    await tester
        .pumpWidget(_boxes(width: 400, cross: CrossAxisAlignment.end));

    expect(tester.getRect(find.byKey(_end)).bottom, 40);
  });

  testWidgets(
      'When the box narrows and widens again, Then it moves between the two '
      'without building either piece anew', (tester) async {
    _Kept.inits = 0;
    await tester.pumpWidget(_boxes(width: 400, end: const _Kept()));
    expect(_sideBySide(tester), isTrue);

    await tester.pumpWidget(_boxes(width: 300, end: const _Kept()));
    expect(_sideBySide(tester), isFalse);
    await tester.pumpWidget(_boxes(width: 400, end: const _Kept()));
    expect(_sideBySide(tester), isTrue);
    expect(_Kept.inits, 1);
  });

  testWidgets(
      'Given text that fits at the usual size, When the reader doubles the '
      'text size, Then it stacks — the text measures itself', (tester) async {
    Widget words(double scale) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                // The test font draws every character 1 em wide: 200 + 100 px.
                child: SideBySideWhenFits(
                  start: Text('Itineraries',
                      key: _start, style: const TextStyle(fontSize: 18.18)),
                  end: Text('Shared',
                      key: _end, style: const TextStyle(fontSize: 16.6)),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(words(1));
    expect(_sideBySide(tester), isTrue);

    await tester.pumpWidget(words(2));
    expect(_sideBySide(tester), isFalse);
  });
}
