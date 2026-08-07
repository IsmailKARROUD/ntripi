// features/auth/providers/legal_provider.dart — the three legal documents.
//
// One GET /auth/tos carries the Terms, the Community Guidelines AND the
// Privacy Policy, so all three consumers (the signup agreement, the Google
// consent sheet, and the re-acceptance gate) share a single request.
//
// The provider watches localeProvider: switching the in-app language re-fetches
// so the sheet shows the same translation the browser pages would.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';

/// Which of the three documents a sheet should show.
enum LegalDoc { terms, guidelines, privacy }

/// One legal document: its body plus, for translations, the clause saying the
/// English version prevails. `notice` is empty for English.
class LegalDocument {
  final String body;
  final String notice;

  const LegalDocument({required this.body, required this.notice});
}

class LegalDocuments {
  final String tosVersion;
  final Map<LegalDoc, LegalDocument> docs;

  const LegalDocuments({required this.tosVersion, required this.docs});

  LegalDocument operator [](LegalDoc doc) => docs[doc]!;

  factory LegalDocuments.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] as String?) ?? '';
    return LegalDocuments(
      tosVersion: s('version'),
      docs: {
        LegalDoc.terms:
            LegalDocument(body: s('summary'), notice: s('notice_terms')),
        LegalDoc.guidelines:
            LegalDocument(body: s('guidelines'), notice: s('notice_guidelines')),
        LegalDoc.privacy:
            LegalDocument(body: s('privacy'), notice: s('notice_privacy')),
      },
    );
  }
}

/// Errors are NOT swallowed here — the sheet needs them to offer a retry.
/// The previous implementation caught and dropped them, which is how a failed
/// fetch turned into a permanent "Loading…".
final legalDocumentsProvider = FutureProvider<LegalDocuments>((ref) async {
  final lang = ref.watch(localeProvider).languageCode;
  final data = await ref.read(authRepositoryProvider).fetchTos(lang: lang);
  return LegalDocuments.fromJson(data);
});
