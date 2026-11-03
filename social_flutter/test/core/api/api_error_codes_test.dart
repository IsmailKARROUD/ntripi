// test/core/api/api_error_codes_test.dart
//
// A code with no case here falls through to the server's English `detail` in
// every locale. These three were translated in all six .arb files long before
// anything mapped them.

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_error_codes.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/l10n/app_localizations_en.dart';
import 'package:ntripi/l10n/app_localizations_fr.dart';

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

  group('email_unavailable, the address of an erased suspended account', () {
    // How each language would give the reason away, if a rewording ever did.
    const giveaways = {
      'en': ['suspend', 'banned', 'blocked'],
      'fr': ['suspendu', 'banni', 'bloqué'],
      'es': ['suspendid', 'bloquead', 'expulsad'],
      'de': ['gesperrt', 'sperre', 'blockiert'],
      'ar': ['موقوف', 'حظر', 'محظور'],
      'zh': ['停用', '封', '屏蔽'],
    };

    for (final lang in giveaways.keys) {
      test(
          'Given a reader in "$lang", '
          'When the code is localized, '
          'Then they get their own string and no reason', () {
        final l10n = lookupAppLocalizations(Locale(lang));

        final message = localizedApiError('email_unavailable', l10n);

        expect(message, l10n.apiErrorEmailUnavailable);
        expect(message, isNotEmpty);
        if (lang != 'en') expect(message, isNot(en.apiErrorEmailUnavailable));
        // Anyone can type anyone's address at sign-up: the message must not
        // tell them that person was suspended.
        for (final word in giveaways[lang]!) {
          expect(message!.toLowerCase(), isNot(contains(word)));
        }
      });
    }
  });

  test('an unknown code still returns null so the caller can fall back', () {
    expect(localizedApiError('no_such_code', en), isNull);
  });
}
