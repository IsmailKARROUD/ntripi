// test/features/help/help_center_screen_test.dart
//
// Widget tests for the Help Center: the sections it advertises, and the FAQ
// rows expanding and collapsing in place.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/help/presentation/help_center_screen.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/l10n/app_localizations_en.dart';

final _en = AppLocalizationsEn();

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HelpCenterScreen(),
      ),
    );

Future<void> _pumpScreen(WidgetTester tester) async {
  // Tall viewport: the FAQ card alone overflows the default 800 px surface, and
  // a lazy ListView never builds the sections below it.
  tester.view.physicalSize = const Size(500, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(_host(container));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('HelpCenterScreen', () {
    testWidgets(
        'Given the screen builds, '
        'Then it shows the three section labels', (tester) async {
      await _pumpScreen(tester);

      expect(find.text(_en.helpCenterFaqLabel.toUpperCase()), findsOneWidget);
      expect(
          find.text(_en.helpCenterGetHelpLabel.toUpperCase()), findsOneWidget);
      expect(find.text(_en.helpCenterLegalLabel.toUpperCase()), findsOneWidget);
    });

    testWidgets(
        'Given the screen builds, '
        'Then the support rows moved out of Settings are all present',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.text(_en.settingsReportBug), findsOneWidget);
      expect(find.text(_en.helpCenterContactSupport), findsOneWidget);
      expect(find.text(_en.abuseContact), findsOneWidget);
      expect(find.text(_en.helpCenterGeneralEnquiries), findsOneWidget);
      expect(find.text(_en.accountStatusTitle), findsOneWidget);
      // Terms and Privacy are separate rows now — the sheet takes one document.
      expect(find.text(_en.registerTosTitle), findsOneWidget);
      expect(find.text(_en.registerPrivacyPolicy), findsOneWidget);
      expect(find.text(_en.registerGuidelinesTitle), findsOneWidget);
    });

    testWidgets(
        'Given a collapsed FAQ row, '
        'When it is tapped, Then the answer appears and tapping again hides it',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.text(_en.faqItineraryA), findsNothing);

      await tester.tap(find.text(_en.faqItineraryQ));
      await tester.pumpAndSettle();
      expect(find.text(_en.faqItineraryA), findsOneWidget);

      await tester.tap(find.text(_en.faqItineraryQ));
      await tester.pumpAndSettle();
      expect(find.text(_en.faqItineraryA), findsNothing);
    });

    testWidgets(
        'Given one FAQ row is open, '
        'When another is opened, Then both stay open — they are independent',
        (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.text(_en.faqItineraryQ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.faqTracksQ));
      await tester.pumpAndSettle();

      expect(find.text(_en.faqItineraryA), findsOneWidget);
      expect(find.text(_en.faqTracksA), findsOneWidget);
    });
  });
}
