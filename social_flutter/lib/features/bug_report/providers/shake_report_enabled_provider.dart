// features/bug_report/providers/shake_report_enabled_provider.dart
//
// Whether shaking the phone opens the bug reporter. On by default — the gesture
// is only discoverable if it works out of the box — but an off switch is not
// optional: an accelerometer trigger that a user cannot silence is the single
// most complained-about version of this feature.
//
// Persisted the same way as the locale and theme preferences (see
// core/providers/locale_provider.dart): secure storage, async load, sync default
// so the first frame never blocks.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kShakeReportKey = 'ntripi_shake_report_enabled';

const _storage = FlutterSecureStorage();

class ShakeReportEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final saved = await _storage.read(key: _kShakeReportKey);
    // null (first launch) or an unknown value means "not turned off yet".
    state = saved != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _storage.write(key: _kShakeReportKey, value: enabled.toString());
  }
}

final shakeReportEnabledProvider =
    NotifierProvider<ShakeReportEnabledNotifier, bool>(
  ShakeReportEnabledNotifier.new,
);
