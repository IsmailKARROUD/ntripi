// features/itineraries/presentation/widgets/edit_lock_lost_notice.dart
//
// What a half-filled form shows after its editing claim was taken over.
//
// The rule this exists to enforce: the person who gets ejected is almost
// certainly mid-edit, and their unsaved text is now the ONLY copy of it. So
// nothing here pops the route, clears a controller, or disables a field. Save
// is disabled — that would fail anyway — and everything else stays exactly as
// they left it, with two ways out that both preserve the work: take the session
// back, or copy the text somewhere else first.
//
// A snackbar would be wrong for the same reason: it disappears, and the user
// needs to still be able to see why Save stopped working two minutes later.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class EditLockLostNotice extends StatelessWidget {
  const EditLockLostNotice({
    super.key,
    required this.holder,
    required this.onReclaim,
    this.copyText,
    this.busy = false,
  });

  /// Who has it now, when the server said so. Null when the claim is simply
  /// gone — the message drops the name rather than inventing one.
  final EditLock? holder;

  final Future<void> Function() onReclaim;

  /// The user's unsaved prose, for the copy action. Null hides the button — a
  /// form with nothing typed in it has nothing to rescue.
  final String? copyText;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final name = holder?.displayLabel;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: nt.cautionBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.lock_clock_rounded, size: 18, color: nt.cautionFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.editLockLostTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: nt.cautionFg,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            name == null
                ? l10n.editLockLostMessageUnknown
                : l10n.editLockLostMessage(name),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: nt.cautionFg),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : () => onReclaim(),
                style: TextButton.styleFrom(foregroundColor: nt.cautionFg),
                child: Text(l10n.editLockReclaim),
              ),
              if (copyText != null && copyText!.trim().isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: copyText!));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.editLockCopied)),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: nt.cautionFg),
                  child: Text(l10n.editLockCopyText),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
