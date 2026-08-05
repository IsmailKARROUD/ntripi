// features/bug_report/presentation/bug_report_localizations.dart
//
// Translates the `feedback` package's built-in chrome (the Navigate/Draw toggle
// and its submit label) using Ntripi's own ARB strings.
//
// A delegate is required rather than just reading AppLocalizations.of(context):
// that chrome renders inside FeedbackApp's own Localizations scope, which the
// package builds from the delegates handed to BetterFeedback and nothing else.
// So the delegate loads AppLocalizations itself for the requested locale.

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class NtripiFeedbackLocalizationsDelegate
    extends LocalizationsDelegate<FeedbackLocalizations> {
  const NtripiFeedbackLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<FeedbackLocalizations> load(Locale locale) async {
    return _NtripiFeedbackLocalizations(
      await AppLocalizations.delegate.load(locale),
    );
  }

  @override
  bool shouldReload(NtripiFeedbackLocalizationsDelegate old) => false;
}

class _NtripiFeedbackLocalizations extends FeedbackLocalizations {
  final AppLocalizations _l10n;

  const _NtripiFeedbackLocalizations(this._l10n);

  @override
  String get submitButtonText => _l10n.bugReportSubmit;

  @override
  String get feedbackDescriptionText => _l10n.bugReportHint;

  @override
  String get navigate => _l10n.bugReportNavigate;

  @override
  String get draw => _l10n.bugReportDraw;
}
