// test/widgets/content_column_test.dart — the one width rule: a phone fills
// the column, a wide window centres it at 600 px, the tabs' side bar fits
// beside it from 760 px, and snackbars are as wide as its content.
//
// Beside the side bar a tab reaches the window's far edge, so the column keeps
// to the window's centre by leaving the bar's width free at its own end — and a
// floating button can stand in the room beside it, or at its corner when there
// is none.

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

/// [screen] where the tabs' shell puts it beside its side bar: the bar's
/// width taken at the start edge, the screen reaching the window's far edge.
Widget _besideSideBar(Widget screen,
        {TextDirection direction = TextDirection.ltr}) =>
    Directionality(
      textDirection: direction,
      child: Row(
        children: [
          const SizedBox(width: kSideBarWidth),
          Expanded(child: SideBarInset(width: kSideBarWidth, child: screen)),
        ],
      ),
    );

/// A Scaffold whose button stands where [ColumnFabLocation] puts it.
Widget _fabScreen([double inset = 0]) => Scaffold(
      body: const ContentColumn(child: SizedBox.expand()),
      floatingActionButtonLocation: ColumnFabLocation(inset),
      floatingActionButton: FloatingActionButton.extended(
        key: _content,
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('New itinerary'),
      ),
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

  for (final direction in TextDirection.values) {
    testWidgets(
        'Given a screen beside the side bar (${direction.name}), Then its '
        'column is centred on the window, not on the screen', (tester) async {
      _window(tester, const Size(1024, 768));
      await _pump(
        tester,
        _besideSideBar(
          const Scaffold(
            body: ContentColumn(child: SizedBox.expand(key: _content)),
          ),
          direction: direction,
        ),
      );

      final rect = tester.getRect(find.byKey(_content));
      expect(rect.width, kContentMaxWidth);
      expect(rect.center.dx, 512);
    });
  }

  testWidgets(
      'Given a scroll view across the screen, Then a sliver held to the column '
      'lines up with the column, while a sliver left free spans the screen',
      (tester) async {
    _window(tester, const Size(1024, 768));
    await _pump(
      tester,
      _besideSideBar(
        const Scaffold(
          body: CustomScrollView(slivers: [
            SliverContentColumn(
              sliver: SliverToBoxAdapter(
                  child: SizedBox(key: _content, height: 100)),
            ),
            SliverToBoxAdapter(
                child: SizedBox(key: Key('free'), height: 100)),
          ]),
        ),
      ),
    );

    final column = tester.getRect(find.byKey(_content));
    expect(column.width, kContentMaxWidth);
    expect(column.center.dx, 512);
    expect(tester.getRect(find.byKey(const Key('free'))),
        const Rect.fromLTWH(kSideBarWidth, 100, 1024 - kSideBarWidth, 100));
  });

  testWidgets(
      'Given a phone, Then the button stands exactly where endFloat puts it',
      (tester) async {
    _window(tester, const Size(390, 844));
    await _pump(tester, _fabScreen());
    final column = tester.getRect(find.byKey(_content));

    await _pump(
      tester,
      Scaffold(
        body: const SizedBox.expand(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: FloatingActionButton.extended(
          key: _content,
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('New itinerary'),
        ),
      ),
    );
    expect(column, tester.getRect(find.byKey(_content)));
  });

  testWidgets(
      'Given room beside the column, Then the button stands in the window\'s '
      'far corner, off the content', (tester) async {
    _window(tester, const Size(1440, 900));
    await _pump(tester, _besideSideBar(_fabScreen(kSideBarWidth)));

    expect(tester.getRect(find.byKey(_content)).right, 1440 - 16);
  });

  testWidgets(
      'Given too little room beside the column, Then the button stands at the '
      'column\'s own corner, over the content', (tester) async {
    _window(tester, const Size(1024, 768));
    await _pump(tester, _besideSideBar(_fabScreen(kSideBarWidth)));

    // The column ends at 812 (centred on 512); the room after it, 212 px,
    // cannot hold the button and its two margins.
    expect(tester.getRect(find.byKey(_content)).right, 812 - 16);
  });

  testWidgets(
      'Given right-to-left with room beside the column, Then the button '
      'stands in the window\'s far left corner', (tester) async {
    _window(tester, const Size(1440, 900));
    await _pump(
      tester,
      _besideSideBar(_fabScreen(kSideBarWidth),
          direction: TextDirection.rtl),
    );

    expect(tester.getRect(find.byKey(_content)).left, 16);
  });

  test('Given the same inset, Then two locations are equal — the Scaffold '
      'moves the button only when the place really changes', () {
    expect(const ColumnFabLocation(80), const ColumnFabLocation(80));
    expect(const ColumnFabLocation(80), isNot(const ColumnFabLocation(0)));
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
