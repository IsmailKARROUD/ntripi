import 'package:social_flutter/l10n/app_localizations.dart';

class UsernameValidator {
  static final _pattern =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{2,28}[a-zA-Z0-9]$');
  static final _consecutive = RegExp(r'[._]{2,}');

  static bool isValidFormat(String v) => _pattern.hasMatch(v);
  static bool hasConsecutiveSpecial(String v) => _consecutive.hasMatch(v);

  /// Returns null if valid, or a localized error message if invalid.
  static String? validate(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) return l10n.usernameRequired;
    final v = value.trim();
    if (v.length < 4) return l10n.usernameTooShort;
    if (v.length > 30) return l10n.usernameTooLong;
    if (!isValidFormat(v)) return l10n.usernameInvalidFormat;
    if (hasConsecutiveSpecial(v)) return l10n.usernameConsecutiveSpecial;
    return null;
  }
}

class DisplayNameValidator {
  /// Returns null if valid (including empty — display name is optional).
  static String? validate(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > 50) return l10n.displayNameTooLong;
    return null;
  }
}
