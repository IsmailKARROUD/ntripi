// features/itineraries/presentation/widgets/edit_lock_banner.dart
//
// "Ana is editing · away · you can take over in 2:41".
//
// The countdown ticks locally, but every fact in it is the server's:
// [EditLock.state] is a word the server chose, and the countdown is arithmetic
// on the server's absolute takeover_available_at. The client never decides that
// a claim has gone stale — two clocks would disagree and only one of them is
// consulted by the write path.
//
// The Take over button is enabled from [EditSession.canTakeOverNow], which is
// likewise the server's answer read back. Pressing it when the server says no
// is not a bug the UI has to prevent; it is a 423 the UI would then have to
// explain, which is worse than a disabled button.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

class EditLockBanner extends StatefulWidget {
  const EditLockBanner({
    super.key,
    required this.lock,
    required this.canTakeOverNow,
    required this.onTakeOver,
    this.isOwner = false,
    this.busy = false,
  });

  final EditLock lock;

  /// Whether the server would currently allow this viewer to displace the
  /// claim. Not recomputed here.
  final bool canTakeOverNow;

  final VoidCallback onTakeOver;

  /// Owners never wait out the timeout, so the countdown becomes informational
  /// rather than a gate and the banner says so.
  final bool isOwner;

  final bool busy;

  @override
  State<EditLockBanner> createState() => _EditLockBannerState();
}

class _EditLockBannerState extends State<EditLockBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // One second, only while a countdown is actually on screen. Nothing here
    // reaches the network — it re-renders arithmetic on a timestamp we already
    // have, which is why polling for a fresher lock is a separate concern.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _formatRemaining(Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final lock = widget.lock;
    final remaining = lock.remainingUntilTakeover();

    // cautionBg, not dangerTint: somebody is working, nothing has gone wrong.
    final background = nt.cautionBg;
    final foreground = nt.cautionFg;

    final String headline;
    if (lock.isYou) {
      headline = l10n.editLockYouElsewhere;
    } else if (lock.state == EditLockState.active) {
      headline = l10n.editLockSomeoneEditing(lock.displayLabel);
    } else {
      // idle and takeable both read as "away" — the difference between them is
      // the countdown line below, not the person's status.
      headline = l10n.editLockSomeoneEditingIdle(lock.displayLabel);
    }

    final String? subline;
    if (lock.isYou) {
      subline = null; // "Continue here" says everything the second line would.
    } else if (widget.isOwner) {
      subline = l10n.editLockOwnerCanReclaim;
    } else if (remaining == Duration.zero) {
      subline = l10n.editLockAvailableNow;
    } else {
      subline = l10n.editLockAvailableIn(_formatRemaining(remaining));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          UserAvatar(avatarUrl: lock.holderAvatarUrl, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headline,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                ),
                if (subline != null)
                  Text(
                    subline,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: foreground.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed:
                widget.busy || !widget.canTakeOverNow ? null : widget.onTakeOver,
            style: TextButton.styleFrom(foregroundColor: foreground),
            child: Text(
              lock.isYou ? l10n.editLockMoveHere : l10n.editLockTakeOver,
            ),
          ),
        ],
      ),
    );
  }
}
