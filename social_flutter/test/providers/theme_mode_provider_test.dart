// test/providers/theme_mode_provider_test.dart
//
// Unit tests for ThemeModeNotifier — the persisted System/Light/Dark
// preference behind the settings theme picker.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/theme_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('ThemeModeNotifier', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test(
        'Given empty storage, '
        'When the provider builds, '
        'Then the state is ThemeMode.system', () async {
      final container = createContainer();

      expect(container.read(themeModeProvider), ThemeMode.system);
      await pumpEventQueue();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test(
        'Given a stored "dark" preference, '
        'When the provider builds, '
        'Then the state becomes ThemeMode.dark once loaded', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_theme_mode': 'dark',
      });
      final container = createContainer();

      // sync default until the async storage read resolves
      expect(container.read(themeModeProvider), ThemeMode.system);
      await pumpEventQueue();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test(
        'Given an unknown stored value, '
        'When the provider builds, '
        'Then the state falls back to ThemeMode.system', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_theme_mode': 'sepia',
      });
      final container = createContainer();

      await pumpEventQueue();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test(
        'Given the provider is built, '
        'When setMode(ThemeMode.light) is called, '
        'Then the state updates immediately and "light" is persisted',
        () async {
      final container = createContainer();
      await pumpEventQueue();

      final future =
          container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

      // optimistic: state flips before the storage write completes
      expect(container.read(themeModeProvider), ThemeMode.light);
      await future;

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'ntripi_theme_mode'), 'light');
    });

    test(
        'Given a previously persisted mode, '
        'When a new container builds (fresh app start), '
        'Then the persisted mode is restored', () async {
      final first = createContainer();
      await pumpEventQueue();
      await first.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      final second = createContainer();
      // first read triggers the lazy build + async load
      expect(second.read(themeModeProvider), ThemeMode.system);
      await pumpEventQueue();
      expect(second.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
