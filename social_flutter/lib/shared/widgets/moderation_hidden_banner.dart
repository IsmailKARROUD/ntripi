// shared/widgets/moderation_hidden_banner.dart — "this is hidden" notice.
//
// Shown to the AUTHOR only. Every moderated surface uses this one widget so the
// wording and the appeal affordance stay identical whether the hidden thing is
// an itinerary, a review, or a profile bio.
//
// Only `hidden`/`rejected` ever reach here: `pending` and `flagged` are internal
// states and are deliberately never surfaced (see ModerationStatus).

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class ModerationHiddenBanner extends StatelessWidget {
  /// What is hidden and what that means for this surface.
  final String message;

  /// Moderator's reason, when the server sent one.
  final String? reason;

  /// Opens the appeal composer. Null hides the action — used where the caller
  /// has no target id to appeal against.
  final VoidCallback? onAppeal;

  final EdgeInsetsGeometry padding;

  const ModerationHiddenBanner({
    super.key,
    required this.message,
    this.reason,
    this.onAppeal,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: nt.cautionBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: nt.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility_off_outlined, size: 20, color: nt.cautionFg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.hiddenBannerTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: nt.cautionFg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: nt.cautionFg),
            ),
            if (reason != null && reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l10n.hiddenBannerReason(reason!),
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: nt.cautionFg,
                ),
              ),
            ],
            if (onAppeal != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('moderationAppealButton'),
                  onPressed: onAppeal,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: nt.cautionFg,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l10n.hiddenAppealAction),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
