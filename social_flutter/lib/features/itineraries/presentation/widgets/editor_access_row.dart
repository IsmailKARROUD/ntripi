// presentation/widgets/editor_access_row.dart — an editor's way out.
//
// The owner can revoke an editor from "Who can edit"; until now the editor had
// no matching exit and had to ask. This row is that exit, and its placement is
// the whole design: it sits at the very bottom of the detail screen, past every
// stop, so reaching it takes a deliberate scroll. Nothing that ejects you from
// a trip belongs in the hero chrome next to back, share and the pencil, where a
// thumb already rests.
//
// It renders state and nothing else — the caller owns the permission gate and
// the confirm dialog, so this widget stays testable without a provider scope.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class EditorAccessRow extends StatelessWidget {
  const EditorAccessRow({super.key, required this.onLeave});

  /// Null while a leave is already in flight, which also greys the action out.
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;

    return Container(
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: nt.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: nt.text2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.editorsLeaveRowTitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: nt.text2, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            // A plain text button, not a filled or pill one: this is the least
            // emphatic control on the page on purpose.
            child: TextButton(
              onPressed: onLeave,
              style: TextButton.styleFrom(foregroundColor: nt.danger),
              child: Text(
                l10n.editorsLeaveAction,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
