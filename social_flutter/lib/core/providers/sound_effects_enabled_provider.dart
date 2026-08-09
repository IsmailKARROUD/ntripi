// core/providers/sound_effects_enabled_provider.dart — UI sound cues on/off.
//
// On by default: a cue nobody hears is a cue nobody knows to look for. But an
// app that makes noise with no way to stop it is the complaint an off switch
// exists to prevent — the same reasoning as the shake-to-report toggle.
//
// Persisted like the locale, theme and shake preferences: secure storage, async
// load, sync default so the first frame never blocks.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kSoundEffectsKey = 'ntripi_sound_effects_enabled';

// No AndroidOptions: encryptedSharedPreferences is deprecated/ignored in v10+.
const _storage = FlutterSecureStorage();

class SoundEffectsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final saved = await _storage.read(key: _kSoundEffectsKey);
    // null (first launch) or an unknown value means "not turned off yet".
    state = saved != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _storage.write(key: _kSoundEffectsKey, value: enabled.toString());
  }
}

/// Whether the app plays its UI sound cues. Read by [SfxService.play].
final soundEffectsEnabledProvider =
    NotifierProvider<SoundEffectsEnabledNotifier, bool>(
  SoundEffectsEnabledNotifier.new,
);
