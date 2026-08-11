// test/features/help/about_screen_test.dart
//
// About renders from packageInfoProvider, which returns null on web and on any
// platform-channel failure. The version pill must vanish rather than print
// "unknown", and nothing else on the screen may depend on it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/bug_report/data/diagnostics_service.dart';
import 'package:social_flutter/features/help/presentation/about_screen.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/l10n/app_localizations_en.dart';

final _en = AppLocalizationsEn();

Future<void> _pumpScreen(WidgetTester tester, {PackageInfo? info}) async {
  tester.view.physicalSize = const Size(500, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [packageInfoProvider.overrideWith((ref) async => info)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AboutScreen', () {
    testWidgets(
        'Given package info is available, '
        'Then the version pill shows version and build', (tester) async {
      await _pumpScreen(
        tester,
        info: PackageInfo(
          appName: 'Ntripi',
          packageName: 'app.ntripi',
          version: '0.3.0',
          buildNumber: '42',
        ),
      );

      expect(find.text('${_en.aboutVersion} 0.3.0 (42)'), findsOneWidget);
    });

    testWidgets(
        'Given package info is unavailable, '
        'Then the pill is omitted rather than showing a placeholder',
        (tester) async {
      await _pumpScreen(tester, info: null);

      expect(find.textContaining(_en.aboutVersion), findsNothing);
      // The rest of the screen is unaffected.
      expect(find.text('Ntripi'), findsOneWidget);
      expect(find.text(_en.aboutTagline), findsOneWidget);
      expect(find.text(_en.aboutLicenses), findsOneWidget);
    });

    testWidgets(
        'Given the screen builds, '
        'Then it links to the website and all three legal documents',
        (tester) async {
      await _pumpScreen(tester, info: null);

      expect(find.text(_en.registerTosTitle), findsOneWidget);
      expect(find.text(_en.registerPrivacyPolicy), findsOneWidget);
      expect(find.text(_en.registerGuidelinesTitle), findsOneWidget);
      // Section label and row share the key, so both instances are expected.
      expect(find.textContaining(_en.aboutWebsite, findRichText: false),
          findsWidgets);
    });
  });
}
