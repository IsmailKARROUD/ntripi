// features/notifications/presentation/widgets/notification_bell.dart
//
// The bell on the profile hero, next to the settings gear.
//
// Wraps the same GlassIconButton the other hero chrome uses, so it reads as one
// control set, and stacks an unread badge on top.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_chrome.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    // A failed or pending count renders no badge rather than a zero or an
    // error — the bell still opens, which is the part that matters.
    final unread = ref.watch(notificationBadgeProvider).value?.unread ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: l10n.notificationsTitle,
          onTap: () => context.push('/notifications'),
        ),
        if (unread > 0)
          PositionedDirectional(
            top: -4,
            end: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              decoration: BoxDecoration(
                color: nt.danger,
                borderRadius: BorderRadius.circular(9),
                // Ring in the chrome colour so the badge stays legible over a
                // busy cover photo, the same trick the hero buttons use.
                border: Border.all(color: NtripiBrand.chrome, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                // Past 99 the exact number stops being information.
                unread > 99 ? '99+' : '$unread',
                style: TextStyle(
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: nt.overlayChrome,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
