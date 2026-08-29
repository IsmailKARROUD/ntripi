// test/providers/haptics_enabled_provider_test.dart
//
// Unit tests for HapticsEnabledNotifier — the persisted on/off preference
// behind the settings Haptics switch, read by HapticsService.fire().
//
// The default-on behaviour is the point: only the literal string 'false' turns
// the taps off, so a first launch or a corrupted value leaves them firing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/haptics_enabled_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('HapticsEnabledNotifier', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test(
        'Given empty storage, '
        'When the provider builds, '
        'Then haptics are on', () async {
      final container = createContainer();

      expect(container.read(hapticsEnabledProvider), isTrue);
      await pumpEventQueue();
      expect(container.read(hapticsEnabledProvider), isTrue);
    });

    test(
        'Given a stored "false", '
        'When the provider builds, '
        'Then haptics are off once loaded', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_haptics_enabled': 'false',
      });
      final container = createContainer();

      // sync default until the async storage read resolves
      expect(container.read(hapticsEnabledProvider), isTrue);
      await pumpEventQueue();
      expect(container.read(hapticsEnabledProvider), isFalse);
    });

    test(
        'Given an unknown stored value, '
        'When the provider builds, '
        'Then haptics stay on', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_haptics_enabled': 'maybe',
      });
      final container = createContainer();

      await pumpEventQueue();
      expect(container.read(hapticsEnabledProvider), isTrue);
    });

    test(
        'Given the provider is built, '
        'When setEnabled(false) is called, '
        'Then the state flips immediately and "false" is persisted', () async {
      final container = createContainer();
      await pumpEventQueue();

      final future =
          container.read(hapticsEnabledProvider.notifier).setEnabled(false);

      // optimistic: state flips before the storage write completes
      expect(container.read(hapticsEnabledProvider), isFalse);
      await future;

      const storage = FlutterSecureStorage();
      expect(
        await storage.read(key: 'ntripi_haptics_enabled'),
        'false',
      );
    });

    test(
        'Given the preference was turned off, '
        'When a new container builds (fresh app start), '
        'Then it is still off', () async {
      final first = createContainer();
      await pumpEventQueue();
      await first.read(hapticsEnabledProvider.notifier).setEnabled(false);

      final second = createContainer();
      // first read triggers the lazy build + async load
      expect(second.read(hapticsEnabledProvider), isTrue);
      await pumpEventQueue();
      expect(second.read(hapticsEnabledProvider), isFalse);
    });
  });
}
