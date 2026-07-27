import 'package:social_flutter/l10n/app_localizations.dart';

/// A UI language the app ships translations for.
class AppLocale {
  final String code;
  final String flag;

  /// Native/self name — fallback label when [localeLabel] can't resolve one.
  final String nativeLabel;

  const AppLocale({
    required this.code,
    required this.flag,
    required this.nativeLabel,
  });
}

/// Single source of truth for the app's supported UI languages.
/// Keep in sync with the l10n .arb files (main.dart wires supportedLocales
/// from AppLocalizations.supportedLocales, so no separate list to update).
const List<AppLocale> kAppLocales = [
  AppLocale(code: 'en', flag: '🇬🇧', nativeLabel: 'English'),
  AppLocale(code: 'fr', flag: '🇫🇷', nativeLabel: 'Français'),
  // globe, not a country flag — Arabic spans many countries
  AppLocale(code: 'ar', flag: '🌐', nativeLabel: 'العربية'),
  AppLocale(code: 'es', flag: '🇪🇸', nativeLabel: 'Español'),
  AppLocale(code: 'de', flag: '🇩🇪', nativeLabel: 'Deutsch'),
  AppLocale(code: 'zh', flag: '🇨🇳', nativeLabel: '简体中文'),
];

/// Codes only — for membership checks (e.g. system-locale fallback).
final Set<String> kAppLocaleCodes = {for (final l in kAppLocales) l.code};

/// Localized display name for a UI-language [code], falling back to English.
String localeLabel(AppLocalizations l10n, String code) => switch (code) {
      'fr' => l10n.languageFrench,
      'ar' => l10n.languageArabic,
      'es' => l10n.languageSpanish,
      'de' => l10n.languageGerman,
      'zh' => l10n.languageChinese,
      _ => l10n.languageEnglish,
    };
