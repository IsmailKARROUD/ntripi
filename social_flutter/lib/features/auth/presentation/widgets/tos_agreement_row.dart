// features/auth/presentation/widgets/tos_agreement_row.dart
//
// The checkbox + "I agree to the Terms of Service, Community Guidelines and
// Privacy Policy…" label. Extracted from register_screen.dart once the Google
// consent sheet and the re-acceptance gate needed the identical control —
// three consumers of one agreement, which has to read the same in all of them
// or the record of what was accepted stops meaning anything.
//
// All three documents now open in the in-app sheet: since the Privacy Policy
// became plain text it no longer needs a browser to render.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/presentation/widgets/legal_doc_sheet.dart';
import 'package:social_flutter/features/auth/providers/legal_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

class TosAgreementRow extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onChanged;

  /// The help icon belongs on the signup form, where the row sits among other
  /// labelled fields; the consent sheet and the gate are already all about
  /// this one thing.
  final bool showHelp;

  const TosAgreementRow({
    super.key,
    required this.accepted,
    required this.onChanged,
    this.showHelp = true,
  });

  /// The whole agreement as one string — a screen reader announces the row as
  /// a single labelled checkbox instead of a checkbox and six loose fragments.
  static String semanticsLabel(AppLocalizations l10n) =>
      '${l10n.registerTosAgree}${l10n.registerTos}'
      '${l10n.registerTosComma}${l10n.registerGuidelines}'
      '${l10n.registerTosAnd}${l10n.registerPrivacyPolicy}'
      '${l10n.registerTosSuffix}${l10n.registerTosProhibited}';

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final plain = TextStyle(fontSize: 13, color: nt.text2);

    return Semantics(
      container: true,
      checked: accepted,
      label: semanticsLabel(l10n),
      child: GestureDetector(
        onTap: () => onChanged(!accepted),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Checkbox(
                value: accepted,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                children: [
                  Text(l10n.registerTosAgree, style: plain),
                  _LegalLink(
                    label: l10n.registerTos,
                    onTap: () => showLegalDocSheet(context, LegalDoc.terms),
                  ),
                  Text(l10n.registerTosComma, style: plain),
                  _LegalLink(
                    label: l10n.registerGuidelines,
                    onTap: () => showLegalDocSheet(context, LegalDoc.guidelines),
                  ),
                  Text(l10n.registerTosAnd, style: plain),
                  _LegalLink(
                    label: l10n.registerPrivacyPolicy,
                    onTap: () => showLegalDocSheet(context, LegalDoc.privacy),
                  ),
                  Text(l10n.registerTosSuffix, style: plain),
                  Text(l10n.registerTosProhibited, style: plain),
                ],
              ),
            ),
            if (showHelp)
              FieldHelpIcon(
                helpTitle: l10n.registerTos,
                helpMessage: l10n.registerTosHelp,
                color: nt.text2,
              ),
          ],
        ),
      ),
    );
  }
}

/// One tappable document name inside the agreement label. Kept as a `Wrap`
/// segment rather than a `TextSpan` recognizer to match the rest of the app,
/// and marked `link` so each document stays individually reachable to a screen
/// reader even though the surrounding row announces as a single checkbox.
class _LegalLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LegalLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.nt.forest,
          ),
        ),
      ),
    );
  }
}
