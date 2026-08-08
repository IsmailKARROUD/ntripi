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
// It also collects the date of birth, because a new account needs both and two
// consecutive sheets for one signup would be worse. When Google's People API
// supplied a birthday it arrives as `prefill` and the field starts filled —
// still editable, so it is a prefill rather than a silent assertion.
//
// Returns null when the user declined.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/presentation/widgets/tos_agreement_row.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/date_of_birth_field.dart';

class GoogleConsentResult {
  final DateTime dateOfBirth;
  const GoogleConsentResult({required this.dateOfBirth});
}

Future<GoogleConsentResult?> showGoogleTosConsentSheet(
  BuildContext context, {
  DateTime? prefill,
}) async {
  final nt = context.nt;
  return showModalBottomSheet<GoogleConsentResult>(
    context: context,
    isScrollControlled: true,
    // Not dismissible by tapping away: closing it is a decision, and the only
    // ways out are the explicit Cancel button and the system back gesture.
    isDismissible: false,
    backgroundColor: nt.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _GoogleTosConsentSheet(prefill: prefill),
  );
}

class _GoogleTosConsentSheet extends StatefulWidget {
  final DateTime? prefill;
  const _GoogleTosConsentSheet({this.prefill});

  @override
  State<_GoogleTosConsentSheet> createState() => _GoogleTosConsentSheetState();
}

class _GoogleTosConsentSheetState extends State<_GoogleTosConsentSheet> {
  bool _accepted = false;
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    _dateOfBirth = widget.prefill;
  }

  bool get _canSubmit =>
      _accepted &&
      _dateOfBirth != null &&
      DateOfBirthField.isOldEnough(_dateOfBirth!);

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
            Text(
              l10n.googleConsentDobLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: nt.text2,
              ),
            ),
            const SizedBox(height: 6),
            DateOfBirthField(
              value: _dateOfBirth,
              onChanged: (v) => setState(() => _dateOfBirth = v),
              // Named as Google's when it came from there, so an unexpected
              // date is attributable rather than mysterious.
              hintOverride: widget.prefill != null ? l10n.dobFromGoogle : null,
            ),
            const SizedBox(height: 16),
            TosAgreementRow(
              accepted: _accepted,
              onChanged: (v) => setState(() => _accepted = v),
              showHelp: false,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _canSubmit
                  ? () => Navigator.of(context).pop(
                        GoogleConsentResult(dateOfBirth: _dateOfBirth!),
                      )
                  : null,
              child: Text(l10n.googleTosAccept),
            ),
            const SizedBox(height: 8),
            TextButton(
              // pop(null) — declining and dismissing are the same outcome, and
              // the caller only ever checks for a result.
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
