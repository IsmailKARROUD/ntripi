import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ntripi/shared/data/app_locales.dart';

const _kLocaleKey = 'ntripi_app_locale';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    // Kick off the async load; state updates once storage/system locale resolves.
    // Returning a sync default keeps the first frame from blocking on secure storage.
    _load();
    return const Locale('en');
  }

  Future<void> _load() async {
    final saved = await _storage.read(key: _kLocaleKey);
    if (!ref.mounted) return; // disposed while storage answered
    if (saved != null) {
      // User has previously chosen a language — always honour it.
      state = Locale(saved);
    } else {
      // First launch: the first of the device's languages the app ships — the
      // whole list, not only its head, as the website reads Accept-Language.
      state = firstSupportedLocale(PlatformDispatcher.instance.locales);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    await _storage.write(key: _kLocaleKey, value: locale.languageCode);
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
