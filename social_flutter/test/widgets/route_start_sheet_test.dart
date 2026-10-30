// test/widgets/route_start_sheet_test.dart — the question the route arrow asks,
// on its own: each answer comes back as the start it names, a dismissal as none,
// and both answers can still be reached at the largest text a phone offers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/maps_launcher_service.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/route_start_sheet.dart';
import 'package:ntripi/l10n/app_localizations.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

/// A page whose one button asks the question, opened; every answer is kept.
Future<List<RouteStart?>> _ask(WidgetTester tester) async {
  final answers = <RouteStart?>[];
  await tester.pumpWidget(MaterialApp(
    theme: buildNtripiTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async =>
                answers.add(await showRouteStartSheet(context)),
            child: const Text('Ask'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ask'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  for (final (start, label) in [
    (RouteStart.myLocation, _l10n.routeFromMyLocation),
    (RouteStart.firstStop, _l10n.routeFromFirstStop),
  ]) {
    testWidgets('tapping "$label" closes the question and answers it',
        (tester) async {
      final answers = await _ask(tester);
      expect(find.text(_l10n.openRouteInMaps), findsOneWidget);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(answers, [start]);
      expect(find.text(_l10n.openRouteInMaps), findsNothing);
    });
  }

  testWidgets('Android back closes the question and answers nothing',
      (tester) async {
    final answers = await _ask(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(answers, [null]);
    expect(find.text(_l10n.routeFromMyLocation), findsNothing);
  });

  // The smallest phone each platform still sells, at its largest text: iOS's
  // last accessibility size, Android's 200 %.
  for (final (phone, size, scale) in [
    ('an iPhone SE at its largest accessibility text', const Size(375, 667), 3.12),
    ('a small Android phone at its largest font size', const Size(360, 640), 2.0),
  ]) {
    testWidgets('on $phone, the second answer can still be reached and picked',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final answers = await _ask(tester);

      final last = find.text(_l10n.routeFromFirstStop);
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();

      expect(answers, [RouteStart.firstStop]);
    });
  }
}
