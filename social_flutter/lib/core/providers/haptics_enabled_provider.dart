// core/providers/haptics_enabled_provider.dart — UI haptic cues on/off.
//
// Separate from the sound toggle on purpose. Muting the app in a meeting is
// exactly when the tap is the only feedback left, so one switch governing both
// channels could not express the combination people actually want.
//
// Persisted like the locale, theme, sound and shake preferences: secure
// storage, async load, sync default so the first frame never blocks.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kHapticsKey = 'ntripi_haptics_enabled';

// No AndroidOptions: encryptedSharedPreferences is deprecated/ignored in v10+.
const _storage = FlutterSecureStorage();

class HapticsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final saved = await _storage.read(key: _kHapticsKey);
    // null (first launch) or an unknown value means "not turned off yet".
    state = saved != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _storage.write(key: _kHapticsKey, value: enabled.toString());
  }
}

/// Whether the app fires its haptic cues. Read by [HapticsService.fire].
final hapticsEnabledProvider =
    NotifierProvider<HapticsEnabledNotifier, bool>(
  HapticsEnabledNotifier.new,
);
