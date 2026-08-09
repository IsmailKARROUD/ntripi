// test/providers/sound_effects_enabled_provider_test.dart
//
// Unit tests for SoundEffectsEnabledNotifier — the persisted on/off preference
// behind the settings Sound effects switch, read by SfxService.play().
//
// The default-on behaviour is the point: only the literal string 'false' turns
// the cues off, so a first launch or a corrupted value leaves them audible.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/sound_effects_enabled_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('SoundEffectsEnabledNotifier', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test(
        'Given empty storage, '
        'When the provider builds, '
        'Then sound effects are on', () async {
      final container = createContainer();

      expect(container.read(soundEffectsEnabledProvider), isTrue);
      await pumpEventQueue();
      expect(container.read(soundEffectsEnabledProvider), isTrue);
    });

    test(
        'Given a stored "false", '
        'When the provider builds, '
        'Then sound effects are off once loaded', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_sound_effects_enabled': 'false',
      });
      final container = createContainer();

      // sync default until the async storage read resolves
      expect(container.read(soundEffectsEnabledProvider), isTrue);
      await pumpEventQueue();
      expect(container.read(soundEffectsEnabledProvider), isFalse);
    });

    test(
        'Given an unknown stored value, '
        'When the provider builds, '
        'Then sound effects stay on', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ntripi_sound_effects_enabled': 'maybe',
      });
      final container = createContainer();

      await pumpEventQueue();
      expect(container.read(soundEffectsEnabledProvider), isTrue);
    });

    test(
        'Given the provider is built, '
        'When setEnabled(false) is called, '
        'Then the state flips immediately and "false" is persisted', () async {
      final container = createContainer();
      await pumpEventQueue();

      final future =
          container.read(soundEffectsEnabledProvider.notifier).setEnabled(false);

      // optimistic: state flips before the storage write completes
      expect(container.read(soundEffectsEnabledProvider), isFalse);
      await future;

      const storage = FlutterSecureStorage();
      expect(
        await storage.read(key: 'ntripi_sound_effects_enabled'),
        'false',
      );
    });

    test(
        'Given the preference was turned off, '
        'When a new container builds (fresh app start), '
        'Then it is still off', () async {
      final first = createContainer();
      await pumpEventQueue();
      await first.read(soundEffectsEnabledProvider.notifier).setEnabled(false);

      final second = createContainer();
      // first read triggers the lazy build + async load
      expect(second.read(soundEffectsEnabledProvider), isTrue);
      await pumpEventQueue();
      expect(second.read(soundEffectsEnabledProvider), isFalse);
    });
  });
}
