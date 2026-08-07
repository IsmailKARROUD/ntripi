// features/auth/presentation/widgets/legal_doc_sheet.dart
//
// The bottom sheet that shows a legal document at the point of acceptance.
//
// The sheet watches legalDocumentsProvider from INSIDE its own route rather
// than being handed a value at call time. That is deliberate: showModalBottomSheet
// builds on a separate route, so a parent setState never reaches it. The
// previous version captured a possibly-null body and, if you tapped before the
// fetch resolved — or on any device where the request failed — sat on
// "Loading…" until you closed it.
//
// Three async states, as the project requires: loading, error (with a retry and
// a browser fallback), and data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/providers/legal_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public URL of a document, in the reader's language, for the browser
/// fallback. `?lang=` is honoured by the server's resolve_lang().
String legalDocUrl(LegalDoc doc, String languageCode) {
  final base = switch (doc) {
    LegalDoc.terms => kTermsUrl,
    LegalDoc.guidelines => kGuidelinesUrl,
    LegalDoc.privacy => kPrivacyPolicyUrl,
  };
  return '$base?lang=$languageCode';
}

String legalDocTitle(LegalDoc doc, AppLocalizations l10n) => switch (doc) {
      LegalDoc.terms => l10n.registerTosTitle,
      LegalDoc.guidelines => l10n.registerGuidelinesTitle,
      LegalDoc.privacy => l10n.registerPrivacyPolicy,
    };

void showLegalDocSheet(BuildContext context, LegalDoc doc) {
  final nt = context.nt;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: nt.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _LegalDocSheet(doc: doc),
  );
}

class _LegalDocSheet extends ConsumerWidget {
  final LegalDoc doc;

  const _LegalDocSheet({required this.doc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(legalDocumentsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: nt.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              legalDocTitle(doc, l10n),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: nt.bark,
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: NTripiPeakLoader(size: 64)),
              error: (_, _) => _LegalDocError(doc: doc),
              data: (docs) => _LegalDocBody(
                document: docs[doc],
                controller: sc,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalDocBody extends StatelessWidget {
  final LegalDocument document;
  final ScrollController controller;

  const _LegalDocBody({required this.document, required this.controller});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Empty for English — it is the authoritative text.
          if (document.notice.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: nt.cautionBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                document.notice,
                style: TextStyle(fontSize: 12, color: nt.cautionFg, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            document.body,
            style: TextStyle(fontSize: 14, color: nt.text2, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// Failure is visible and recoverable — the old code swallowed it entirely.
class _LegalDocError extends ConsumerWidget {
  final LegalDoc doc;

  const _LegalDocError({required this.doc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: nt.text3),
            const SizedBox(height: 12),
            Text(
              l10n.legalDocLoadFailed,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: nt.text2, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => ref.invalidate(legalDocumentsProvider),
              child: Text(l10n.retry),
            ),
            const SizedBox(height: 8),
            TextButton(
              // The document is always readable on the website, so an offline
              // or broken API still leaves a way to read what you are accepting.
              onPressed: () => launchUrl(
                Uri.parse(
                  legalDocUrl(doc, ref.read(localeProvider).languageCode),
                ),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(l10n.legalDocOpenInBrowser),
            ),
          ],
        ),
      ),
    );
  }
}
