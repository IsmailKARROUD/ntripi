// test/widgets/theme_picker_test.dart
//
// Widget tests for the Theme row + System/Light/Dark picker inside the
// profile settings bottom sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/theme_mode_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_settings_sheet.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/theme_picker_button.dart';

Widget _host(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildNtripiTheme(),
      darkTheme: buildNtripiDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showProfileSettingsSheet(context, onLogout: () {}),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<ProviderContainer> _openSettingsSheet(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(_host(container));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Theme picker', () {
    testWidgets(
        'Given the settings sheet is open, '
        'Then a Theme row shows the current mode (System)', (tester) async {
      await _openSettingsSheet(tester);

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });

    testWidgets(
        'Given the Theme row is tapped, '
        'Then the picker opens with the three modes and a check on System',
        (tester) async {
      await _openSettingsSheet(tester);

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      expect(find.text('THEME'), findsOneWidget); // picker section title
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      // check mark sits on the System row (current mode)
      final checkIcon = find.byIcon(Icons.check_rounded);
      expect(checkIcon, findsOneWidget);
      expect(
        find.ancestor(of: checkIcon, matching: find.byType(InkWell)).first,
        findsOneWidget,
      );
    });

    testWidgets(
        'Given the picker is open, '
        'When Dark is tapped, '
        'Then the provider switches to dark, persists it and the picker closes',
        (tester) async {
      final container = await _openSettingsSheet(tester);

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      // picker popped: its section title is gone…
      expect(find.text('THEME'), findsNothing);
      // …and the settings row now shows the new mode as its detail
      expect(find.text('Dark'), findsOneWidget);

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_theme_mode'), 'dark');
    });
  });

  group('ThemePickerButton (pre-auth screens)', () {
    testWidgets(
        'Given the pill is tapped, '
        'When Dark is selected from the menu, '
        'Then the provider switches to dark and persists it', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildNtripiTheme(),
            darkTheme: buildNtripiDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Center(child: ThemePickerButton()),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ThemePickerButton));
      await tester.pumpAndSettle();

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_theme_mode'), 'dark');
    });
  });
}
