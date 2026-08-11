// features/help/domain/faq_entries.dart
//
// The Help Center question list. Built from AppLocalizations rather than
// fetched: the answers describe how the app itself works, so they ship with the
// app and stay in step with it — a server-side FAQ would drift out of sync with
// whatever version the reader is holding.

import 'package:social_flutter/l10n/app_localizations.dart';

class FaqEntry {
  final String question;
  final String answer;

  const FaqEntry(this.question, this.answer);
}

List<FaqEntry> faqEntries(AppLocalizations l10n) => [
      FaqEntry(l10n.faqItineraryQ, l10n.faqItineraryA),
      FaqEntry(l10n.faqTracksQ, l10n.faqTracksA),
      FaqEntry(l10n.faqVisibilityQ, l10n.faqVisibilityA),
      FaqEntry(l10n.faqRatingsQ, l10n.faqRatingsA),
      FaqEntry(l10n.faqSaveQ, l10n.faqSaveA),
      FaqEntry(l10n.faqPrivateAccountQ, l10n.faqPrivateAccountA),
      FaqEntry(l10n.faqBlockReportQ, l10n.faqBlockReportA),
      FaqEntry(l10n.faqStaleEditQ, l10n.faqStaleEditA),
    ];
