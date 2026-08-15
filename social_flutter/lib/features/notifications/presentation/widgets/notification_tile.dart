// features/notifications/presentation/widgets/notification_tile.dart
//
// One row of the notification feed. The sentence is built by AppNotification
// from AppLocalizations — this widget only decides how it looks.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final bool isLast;
  final VoidCallback? onTap;

  /// Null offline, and on any surface where the row cannot be removed.
  final VoidCallback? onDelete;

  const NotificationTile({
    super.key,
    required this.notification,
    required this.isLast,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final isModeration =
        notification.type == NotificationType.moderationAction;
    final subtitle = notification.subtitle(l10n);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(18))
              : BorderRadius.zero,
          child: Container(
            // Unread rows are tinted rather than badged: the whole row is the
            // affordance, and a dot would compete with the leading avatar.
            color: notification.read ? null : nt.mist.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Leading(notification: notification, isModeration: isModeration),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title(l10n),
                        style: TextStyle(
                          fontSize: 14,
                          // Unread reads heavier — the tint alone is too subtle
                          // in bright light.
                          fontWeight: notification.read
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: nt.bark,
                          letterSpacing: -0.1,
                          height: 1.3,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: nt.text2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        notification.timeAgo(l10n),
                        style: TextStyle(fontSize: 11.5, color: nt.text3),
                      ),
                    ],
                  ),
                ),
                // The ✕ takes the chevron's place rather than sitting beside it:
                // two trailing glyphs on a three-line row is noise, the tint and
                // the ink splash already say the row is tappable, and a control
                // that deletes has to be the unambiguous one. It is also the
                // only delete affordance on web, where there is no swipe.
                if (onDelete != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: nt.text3),
                    tooltip: l10n.notificationDelete,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 36, height: 36),
                    onPressed: onDelete,
                  ),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.chevron_right, size: 20, color: nt.text3),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsetsDirectional.only(start: 70),
            color: nt.border,
          ),
      ],
    );
  }
}

/// Avatar for anything a person did; an icon pill for system notifications,
/// which have no actor to show.
class _Leading extends StatelessWidget {
  final AppNotification notification;
  final bool isModeration;

  const _Leading({required this.notification, required this.isModeration});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    if (!isModeration && notification.actorId != null) {
      return AvatarInitials(
        name: notification.actorName(l10n),
        avatarUrl: notification.actorAvatarUrl,
      );
    }

    // Only moderation rows carry a subtype, but pairing the checks keeps the
    // icon and the colours keyed off exactly the same condition.
    final isWarning = isModeration && notification.subtype == 'warn';

    // Moderation wears the danger tint — it is the one row the user must not
    // scroll past, and it must not read like a social update. A warning is the
    // exception: nothing was taken down, so it gets the caution pair (the same
    // peach/rust the caution annotation uses) rather than a red that signals a
    // loss which has not happened.
    final (bg, fg) = switch ((isModeration, isWarning)) {
      (true, true) => (nt.cautionBg, nt.cautionFg),
      (true, false) => (nt.dangerTint, nt.danger),
      _ => (nt.mist, nt.forest),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(
        isWarning
            ? Icons.warning_amber_rounded
            : _icon(notification.type),
        size: 20,
        color: fg,
      ),
    );
  }

  static IconData _icon(NotificationType type) => switch (type) {
        NotificationType.followRequest => Icons.person_add_outlined,
        NotificationType.newFollower => Icons.person_add_rounded,
        NotificationType.followAccepted => Icons.how_to_reg_rounded,
        NotificationType.itineraryRated => Icons.star_rounded,
        NotificationType.itinerarySaved => Icons.bookmark_rounded,
        NotificationType.moderationAction => Icons.shield_outlined,
        NotificationType.itineraryEditorAdded => Icons.edit_note_rounded,
        NotificationType.itineraryViewerAdded => Icons.visibility_outlined,
        NotificationType.unknown => Icons.notifications_none_rounded,
      };
}
