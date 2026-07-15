import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class LockedProfileCard extends StatelessWidget {
  final bool isPending;
  final String handle;

  const LockedProfileCard({
    super.key,
    required this.isPending,
    required this.handle,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isPending
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : nt.mist,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPending
                  ? Icons.hourglass_empty_rounded
                  : Icons.lock_rounded,
              size: 28,
              color: isPending
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : nt.forest,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isPending
                ? l10n.followRequestSentTitle
                : l10n.accountIsPrivateTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: nt.bark,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isPending
                ? l10n.followRequestPendingMessage
                : l10n.followToSeeMessage(handle),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: nt.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
