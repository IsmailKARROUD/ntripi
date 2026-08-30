// features/help/presentation/help_center_screen.dart
//
// One place for everything a stuck user might be looking for: how the app
// works, how to reach us, and the legal documents.
//
// The legal rows open the in-app sheet rather than the browser. It already
// fetches the reader's own language and carries a browser fallback on error,
// so sending them out of the app buys nothing and loses the language.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/auth/presentation/widgets/legal_doc_sheet.dart';
import 'package:social_flutter/features/auth/providers/legal_provider.dart';
import 'package:social_flutter/features/help/domain/faq_entries.dart';
import 'package:social_flutter/features/help/presentation/widgets/faq_row.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

// Reading order, stated explicitly rather than taken from LegalDoc.values —
// the enum's declaration order is not a display decision.
const _legalOrder = [LegalDoc.terms, LegalDoc.privacy, LegalDoc.guidelines];

class HelpCenterScreen extends ConsumerWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final faqs = faqEntries(l10n);

    return Scaffold(
      backgroundColor: nt.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: EditorialTopBar(title: l10n.settingsHelpCenter),
              ),
              Container(height: 1, color: nt.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 40),
                  children: [
                    SectionLabel(
                      icon: Icons.help_outline_rounded,
                      label: l10n.helpCenterFaqLabel,
                    ),
                    SectionCard(
                      children: [
                        for (var i = 0; i < faqs.length; i++)
                          FaqRow(
                            question: faqs[i].question,
                            answer: faqs[i].answer,
                            isLast: i == faqs.length - 1,
                          ),
                      ],
                    ),
                    SectionLabel(
                      icon: Icons.support_agent_rounded,
                      label: l10n.helpCenterGetHelpLabel,
                    ),
                    SectionCard(
                      children: [
                        EditorialRow(
                          icon: Icons.bug_report_outlined,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.settingsReportBug,
                          subtitle: l10n.settingsShakeToReportDetail,
                          onTap: () => context.push('/settings/help/report-bug'),
                        ),
                        EditorialRow(
                          icon: Icons.mail_outline_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.helpCenterContactSupport,
                          subtitle: l10n.helpCenterContactSupportSubtitle,
                          onTap: () => launchUrl(
                            Uri(scheme: 'mailto', path: kSupportContactEmail),
                          ),
                        ),
                        // Must match the backend's ABUSE_CONTACT_EMAIL and the
                        // store listing — one address, published in one place.
                        EditorialRow(
                          icon: Icons.report_gmailerrorred_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.abuseContact,
                          subtitle: l10n.abuseContactSubtitle,
                          onTap: () => launchUrl(
                            Uri(scheme: 'mailto', path: kAbuseContactEmail),
                          ),
                        ),
                        // Sits below support so the two rows a user in trouble
                        // needs stay adjacent at the top.
                        EditorialRow(
                          icon: Icons.business_center_outlined,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.helpCenterGeneralEnquiries,
                          subtitle: l10n.helpCenterGeneralEnquiriesSubtitle,
                          onTap: () => launchUrl(
                            Uri(scheme: 'mailto', path: kGeneralContactEmail),
                          ),
                        ),
                        EditorialRow(
                          icon: Icons.shield_outlined,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.accountStatusTitle,
                          subtitle: l10n.helpCenterAccountStatusSubtitle,
                          isLast: true,
                          onTap: () => context.push('/settings/account-status'),
                        ),
                      ],
                    ),
                    SectionLabel(
                      icon: Icons.gavel_rounded,
                      label: l10n.helpCenterLegalLabel,
                    ),
                    SectionCard(
                      children: [
                        for (final doc in _legalOrder)
                          EditorialRow(
                            icon: _legalIcon(doc),
                            iconBg: nt.mist,
                            iconColor: nt.forest,
                            label: legalDocTitle(doc, l10n),
                            isLast: doc == _legalOrder.last,
                            onTap: () => showLegalDocSheet(context, doc),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _legalIcon(LegalDoc doc) => switch (doc) {
        LegalDoc.terms => Icons.gavel_rounded,
        LegalDoc.guidelines => Icons.menu_book_rounded,
        LegalDoc.privacy => Icons.lock_outline_rounded,
      };
}
