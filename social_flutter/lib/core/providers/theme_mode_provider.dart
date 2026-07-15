import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kThemeModeKey = 'ntripi_theme_mode';

// No AndroidOptions: encryptedSharedPreferences is deprecated/ignored in v10+.
const _storage = FlutterSecureStorage();

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Kick off the async load; state updates once storage resolves.
    // Returning a sync default keeps the first frame from blocking on secure storage.
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final saved = await _storage.read(key: _kThemeModeKey);
    state = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      // null (first launch) or unknown value — follow the device setting
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _kThemeModeKey, value: mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
