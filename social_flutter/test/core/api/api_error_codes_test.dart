// test/core/api/api_error_codes_test.dart
//
// A code with no case here falls through to the server's English `detail` in
// every locale. These three were translated in all six .arb files long before
// anything mapped them.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/api/api_error_codes.dart';
import 'package:social_flutter/l10n/app_localizations_en.dart';
import 'package:social_flutter/l10n/app_localizations_fr.dart';

void main() {
  final en = AppLocalizationsEn();

  test('the signup age-gate codes are localized', () {
    expect(localizedApiError('underage', en), en.errorUnderage);
    expect(localizedApiError('dob_required', en), en.errorDobRequired);
  });

  test('a Google account mismatch on delete is localized', () {
    expect(localizedApiError('google_account_mismatch', en),
        en.apiErrorGoogleAccountMismatch);
  });

  test('another locale gets its own string, not the English one', () {
    final fr = AppLocalizationsFr();
    expect(localizedApiError('underage', fr), fr.errorUnderage);
    expect(fr.errorUnderage, isNot(en.errorUnderage));
  });

  test('an unknown code still returns null so the caller can fall back', () {
    expect(localizedApiError('no_such_code', en), isNull);
  });
}
