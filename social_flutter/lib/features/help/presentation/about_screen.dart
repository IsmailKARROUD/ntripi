// features/help/presentation/about_screen.dart
//
// What the app is, which build you are holding, and the links a reviewer or a
// curious user goes looking for.
//
// The version comes from packageInfoProvider, which the bug reporter already
// owns — it returns null on web and on any platform-channel failure rather than
// throwing, so the pill is simply omitted. "Version unknown" would be a worse
// answer than no version at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/auth/presentation/widgets/legal_doc_sheet.dart';
import 'package:social_flutter/features/auth/providers/legal_provider.dart';
import 'package:social_flutter/features/bug_report/data/diagnostics_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final info = ref.watch(packageInfoProvider).value;
    final version = info == null
        ? null
        : '${info.version}${info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})'}';

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
                child: EditorialTopBar(title: l10n.settingsAbout),
              ),
              Container(height: 1, color: nt.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 28, bottom: 40),
                  children: [
                    Text(
                      'Ntripi',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: nt.bark,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.aboutTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.5, color: nt.text2),
                    ),
                    if (version != null) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: nt.mist,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${l10n.aboutVersion} $version',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: nt.forest,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    SectionCard(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Text(
                            l10n.aboutBody,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: nt.text2,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SectionLabel(
                      icon: Icons.link_rounded,
                      label: l10n.aboutWebsite,
                    ),
                    SectionCard(
                      children: [
                        EditorialRow(
                          icon: Icons.public_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.aboutWebsite,
                          detail: _hostOf(kShareBaseUrl),
                          isLast: true,
                          onTap: () => launchUrl(
                            Uri.parse(kShareBaseUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                    SectionLabel(
                      icon: Icons.gavel_rounded,
                      label: l10n.helpCenterLegalLabel,
                    ),
                    SectionCard(
                      children: [
                        EditorialRow(
                          icon: Icons.gavel_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: legalDocTitle(LegalDoc.terms, l10n),
                          onTap: () =>
                              showLegalDocSheet(context, LegalDoc.terms),
                        ),
                        EditorialRow(
                          icon: Icons.lock_outline_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: legalDocTitle(LegalDoc.privacy, l10n),
                          onTap: () =>
                              showLegalDocSheet(context, LegalDoc.privacy),
                        ),
                        EditorialRow(
                          icon: Icons.menu_book_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: legalDocTitle(LegalDoc.guidelines, l10n),
                          onTap: () =>
                              showLegalDocSheet(context, LegalDoc.guidelines),
                        ),
                        EditorialRow(
                          icon: Icons.code_rounded,
                          iconBg: nt.mist,
                          iconColor: nt.forest,
                          label: l10n.aboutLicenses,
                          isLast: true,
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: 'Ntripi',
                            applicationVersion: version,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.aboutCopyright(DateTime.now().year),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: nt.text3),
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

  /// Bare host for the trailing detail — the full scheme+host would wrap on a
  /// narrow row and says nothing extra.
  static String _hostOf(String url) {
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? url : host;
  }
}
