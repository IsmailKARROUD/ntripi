// test/widgets/content_column_test.dart — the one width rule: a phone fills
// the column, a wide window centres it at 600 px, the tabs' side bar fits
// beside it from 760 px, and snackbars are as wide as its content.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/shared/widgets/content_column.dart';

const _content = Key('content');

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget home) => tester.pumpWidget(
      MaterialApp(theme: buildNtripiTheme(), home: home),
    );

void main() {
  test('Given a window, Then the side bar fits from 760 px — the column plus '
      'a bar on each side — and not one pixel before', () {
    expect(kContentMaxWidth, 600);
    expect(kSideBarWidth, 80);
    expect(sideBarFits(759), isFalse);
    expect(sideBarFits(759.9), isFalse);
    expect(sideBarFits(760), isTrue);
    expect(sideBarFits(1440), isTrue);
  });

  testWidgets('Given a phone, Then the column is the whole width',
      (tester) async {
    _window(tester, const Size(390, 844));
    await _pump(
      tester,
      const Scaffold(
        body: ContentColumn(child: SizedBox.expand(key: _content)),
      ),
    );

    expect(tester.getRect(find.byKey(_content)), const Rect.fromLTWH(0, 0, 390, 844));
  });

  testWidgets(
      'Given a wide window, Then the column is 600 px, centred on the window',
      (tester) async {
    _window(tester, const Size(1024, 768));
    await _pump(
      tester,
      const Scaffold(
        body: ContentColumn(child: SizedBox.expand(key: _content)),
      ),
    );

    final rect = tester.getRect(find.byKey(_content));
    expect(rect.width, 600);
    expect(rect.center.dx, 512);
  });

  testWidgets('Given topCenter, Then short content sits at the top',
      (tester) async {
    _window(tester, const Size(1024, 768));
    await _pump(
      tester,
      const Scaffold(
        body: ContentColumn(
          alignment: Alignment.topCenter,
          child: SizedBox(key: _content, width: 900, height: 100),
        ),
      ),
    );

    expect(tester.getRect(find.byKey(_content)),
        const Rect.fromLTWH(212, 0, 600, 100));
  });

  testWidgets(
      'Given a page in the column, Then its app bar and its floating button '
      'line up with the column, and the sides are painted',
      (tester) async {
    _window(tester, const Size(1024, 768));
    await _pump(
      tester,
      ContentPage(
        child: Scaffold(
          appBar: AppBar(title: const Text('Title')),
          body: const SizedBox.expand(),
          floatingActionButton: FloatingActionButton(
            key: _content,
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byType(AppBar)).left, 212);
    expect(tester.getRect(find.byType(AppBar)).width, 600);
    // endFloat: 16 px in from the column's edge, not the window's.
    expect(tester.getRect(find.byKey(_content)).right, 812 - 16);
    final ground = tester.widget<ColoredBox>(find
        .descendant(of: find.byType(ContentPage), matching: find.byType(ColoredBox))
        .first);
    expect(ground.color, tester.element(find.byType(ContentPage)).nt.surface);
  });

  test('Given a phone, Then snackbars keep the theme\'s margins', () {
    final theme = buildNtripiTheme();
    expect(columnSnackBars(theme, 390), same(theme));
    expect(columnSnackBars(theme, 600), same(theme));
  });

  testWidgets(
      'Given a wide window, Then a snackbar is as wide as the column\'s '
      'content and centred on the window', (tester) async {
    _window(tester, const Size(1024, 768));
    await tester.pumpWidget(MaterialApp(
      theme: buildNtripiTheme(),
      builder: (context, child) => Theme(
        data: columnSnackBars(
            Theme.of(context), MediaQuery.sizeOf(context).width),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Saved'))),
            child: const Text('show'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    // The bar itself: the SnackBar's own box is an Align as wide as the window.
    final bar = tester.getRect(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first);
    expect(bar.width, kContentMaxWidth - 32);
    expect(bar.center.dx, 512);
  });
}
