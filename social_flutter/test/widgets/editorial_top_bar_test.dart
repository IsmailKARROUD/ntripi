// test/widgets/editorial_top_bar_test.dart
//
// EditorialTopBar is now the single top bar for the form screens as well as
// the settings ones, so the two things a Material AppBar used to supply for
// free are pinned here:
//
//  1. The back button carries MaterialLocalizations' own "Back" tooltip. An
//     icon with no label is unreadable to a screen reader, and the period
//     screen's own guard test drives the bar through find.byTooltip('Back').
//  2. `leading` replaces that button outright — profile_edit_form is a modal
//     edit with nothing to pop, so it offers Cancel instead and must NOT also
//     render a back arrow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget bar) => tester.pumpWidget(
        MaterialApp(
          theme: buildNtripiTheme(),
          home: Scaffold(body: Column(children: [bar])),
        ),
      );

  testWidgets(
      'Given no leading, When rendered, Then the back button carries the '
      'localized tooltip', (tester) async {
    await pump(tester, const EditorialTopBar(title: 'Settings'));

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Given a leading widget, When rendered, Then it replaces the '
      'back arrow entirely', (tester) async {
    await pump(
      tester,
      EditorialTopBar(
        title: 'Edit Profile',
        centerTitle: true,
        leading: TextButton(onPressed: () {}, child: const Text('Cancel')),
        actions: [TextButton(onPressed: () {}, child: const Text('Save'))],
      ),
    );

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('Given a long title, When rendered, Then it ellipsizes rather '
      'than overflowing', (tester) async {
    await pump(
      tester,
      EditorialTopBar(
        title: 'A title long enough to run past the width of any phone screen',
        actions: [TextButton(onPressed: () {}, child: const Text('Save'))],
      ),
    );

    // A RenderFlex overflow would have been thrown by now.
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.textContaining('A title long'));
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('Given the back button is tapped, When there is a route to pop, '
      'Then it pops', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNtripiTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: EditorialTopBar(title: 'Pushed'),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed'), findsNothing);
  });
}
