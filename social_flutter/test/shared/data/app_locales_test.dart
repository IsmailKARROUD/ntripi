// test/shared/data/app_locales_test.dart
//
// On first launch the app speaks the first of the device's languages it ships —
// walking the whole list, the way the website's resolve_lang walks
// Accept-Language. Reading only the head of the list left a phone set to
// Portuguese, then French, with a French share page and an English sign-in
// screen behind its "See the full trip" button.

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/shared/data/app_locales.dart';

void main() {
  group('firstSupportedLocale', () {
    test('skips a language the app does not ship for the next one it does', () {
      expect(
        firstSupportedLocale(const [Locale('pt', 'BR'), Locale('fr', 'FR')]),
        const Locale('fr'),
      );
    });

    test('falls back to English when none of them is shipped', () {
      expect(firstSupportedLocale(const [Locale('it')]), const Locale('en'));
      expect(firstSupportedLocale(const []), const Locale('en'));
    });

    test('takes the first shipped one, not a later one', () {
      expect(
        firstSupportedLocale(const [Locale('ar', 'MA'), Locale('fr')]),
        const Locale('ar'),
      );
    });

    test('drops the region and script — the app ships languages', () {
      expect(
        firstSupportedLocale(const [
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        ]),
        const Locale('zh'),
      );
      expect(firstSupportedLocale(const [Locale('en', 'US')]), const Locale('en'));
    });
  });
}
