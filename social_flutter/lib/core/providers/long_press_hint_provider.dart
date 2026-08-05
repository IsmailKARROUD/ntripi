// core/providers/long_press_hint_provider.dart — "long-press to edit" tip seen flag.
//
// Long-press has no visible affordance by design, so owners are shown the tip
// once on their own itinerary and never again.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kLongPressHintKey = 'ntripi_longpress_hint_seen';

// No AndroidOptions: encryptedSharedPreferences is deprecated/ignored in v10+.
const _storage = FlutterSecureStorage();

class LongPressHintNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Seed as "seen" so a slow storage read can never flash the tip at someone
    // who already dismissed it; _load flips it back on a genuine first launch.
    _load();
    return true;
  }

  Future<void> _load() async {
    final saved = await _storage.read(key: _kLongPressHintKey);
    state = saved == 'true';
  }

  Future<void> markSeen() async {
    if (state) return;
    state = true;
    await _storage.write(key: _kLongPressHintKey, value: 'true');
  }
}

/// True once the owner has been shown the long-press tip.
final longPressHintSeenProvider =
    NotifierProvider<LongPressHintNotifier, bool>(LongPressHintNotifier.new);
