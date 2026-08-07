// features/auth/presentation/widgets/google_tos_consent_sheet.dart
//
// Consent step for a brand-new Google account.
//
// Consent-on-demand, not consent-first: only the server knows whether an ID
// token means "sign in" or "create an account", so the caller posts the token,
// gets 400 `tos_required` back if it is a signup, shows this sheet, and retries
// the same token with the flag set. Asking before the picker would re-prompt
// every returning Google user at every sign-in.
//
// Returns true when the user accepted.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/presentation/widgets/tos_agreement_row.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Future<bool> showGoogleTosConsentSheet(BuildContext context) async {
  final nt = context.nt;
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Not dismissible by tapping away: closing it is a decision, and the only
    // ways out are the explicit Cancel button and the system back gesture.
    isDismissible: false,
    backgroundColor: nt.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _GoogleTosConsentSheet(),
  );
  return accepted ?? false;
}

class _GoogleTosConsentSheet extends StatefulWidget {
  const _GoogleTosConsentSheet();

  @override
  State<_GoogleTosConsentSheet> createState() => _GoogleTosConsentSheetState();
}

class _GoogleTosConsentSheetState extends State<_GoogleTosConsentSheet> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: nt.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.googleTosTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: nt.bark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.googleTosSubtitle,
              style: TextStyle(fontSize: 14, color: nt.text2, height: 1.5),
            ),
            const SizedBox(height: 20),
            TosAgreementRow(
              accepted: _accepted,
              onChanged: (v) => setState(() => _accepted = v),
              showHelp: false,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed:
                  _accepted ? () => Navigator.of(context).pop(true) : null,
              child: Text(l10n.googleTosAccept),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
