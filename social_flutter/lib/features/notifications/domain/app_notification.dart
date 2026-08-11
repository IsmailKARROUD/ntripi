// features/notifications/domain/app_notification.dart
//
// One row of the in-app notification feed.
//
// The server sends structured references — type, actor, entity — and never a
// rendered sentence. The text is built here from AppLocalizations, which is the
// only way the same row can read correctly in all six locales and can pick up a
// display name that moderation changed after the fact.

import 'package:social_flutter/l10n/app_localizations.dart';

/// What happened. `unknown` is deliberate: a newer backend must never crash a
/// deployed client, so an unrecognised type degrades to a generic row rather
/// than throwing (same rule as ModerationStatus.fromString).
enum NotificationType {
  followRequest,
  newFollower,
  followAccepted,
  itineraryRated,
  itinerarySaved,
  moderationAction,
  unknown;

  static NotificationType fromString(String? value) => switch (value) {
        'follow_request' => NotificationType.followRequest,
        'new_follower' => NotificationType.newFollower,
        'follow_accepted' => NotificationType.followAccepted,
        'itinerary_rated' => NotificationType.itineraryRated,
        'itinerary_saved' => NotificationType.itinerarySaved,
        'moderation_action' => NotificationType.moderationAction,
        _ => NotificationType.unknown,
      };
}

class AppNotification {
  final String id;
  final NotificationType type;

  /// The moderation action name ("hide", "auto_hide_sla", …) on
  /// moderationAction rows, null everywhere else.
  final String? subtype;
  final DateTime createdAt;
  final bool read;

  /// Null for system rows (moderation) and for an actor who deleted their
  /// account. `actorDisplayName` is also null when moderation hid it — the
  /// @username fallback below covers both cases identically.
  final String? actorId;
  final String? actorUsername;
  final String? actorDisplayName;
  final String? actorAvatarUrl;

  final String? entityType;
  final String? entityId;

  /// Null when the entity no longer exists. The reference is polymorphic and
  /// unenforced server-side, so a missing target is expected, not an error.
  final String? entityTitle;

  const AppNotification({
    required this.id,
    required this.type,
    required this.subtype,
    required this.createdAt,
    required this.read,
    required this.actorId,
    required this.actorUsername,
    required this.actorDisplayName,
    required this.actorAvatarUrl,
    required this.entityType,
    required this.entityId,
    required this.entityTitle,
  });

  /// Who to show. Matches the app-wide fallback: a hidden display name degrades
  /// to the handle rather than to an empty string.
  String actorName(AppLocalizations l10n) {
    final name = actorDisplayName;
    if (name != null && name.isNotEmpty) return name;
    final handle = actorUsername;
    if (handle != null && handle.isNotEmpty) return '@$handle';
    return l10n.notificationSomeone;
  }

  String title(AppLocalizations l10n) {
    final actor = actorName(l10n);
    return switch (type) {
      NotificationType.followRequest => l10n.notificationFollowRequest(actor),
      NotificationType.newFollower => l10n.notificationNewFollower(actor),
      NotificationType.followAccepted => l10n.notificationFollowAccepted(actor),
      NotificationType.itineraryRated => l10n.notificationRated(actor),
      NotificationType.itinerarySaved => l10n.notificationSaved(actor),
      NotificationType.moderationAction => _moderationTitle(l10n),
      // A type this build has never heard of. Still worth a row — it tells the
      // user something happened and the screen keeps working.
      NotificationType.unknown => l10n.notificationGeneric,
    };
  }

  String _moderationTitle(AppLocalizations l10n) {
    final title = entityTitle;
    // A warning is against the person, not a piece of content — it has no
    // entity title, and it must be checked before the hide fallthrough below
    // or it would read as "one of your itineraries was hidden".
    if (subtype == 'warn') return l10n.notificationWarned;
    // 'delete' is the operator's hard removal; everything else in the family is
    // a hide, provisional and appealable.
    if (subtype == 'delete') {
      return title == null
          ? l10n.notificationRemovedUntitled
          : l10n.notificationRemoved(title);
    }
    return title == null
        ? l10n.notificationHiddenUntitled
        : l10n.notificationHidden(title);
  }

  /// The secondary line: what the notification is about, when there is one.
  String? subtitle(AppLocalizations l10n) => switch (type) {
        NotificationType.itineraryRated ||
        NotificationType.itinerarySaved =>
          entityTitle,
        // The moderation row already names the itinerary in its title; this
        // line tells the author what they can do about it. A warning gets its
        // own line: nothing was taken down, so "tap for details" undersells
        // that this is a permanent record they can contest.
        NotificationType.moderationAction => subtype == 'warn'
            ? l10n.notificationWarnedDetail
            : l10n.notificationTapForDetails,
        _ => null,
      };

  /// Where tapping goes. Null means the row is not tappable.
  ///
  /// Moderation always routes to Account status: the appeal button already
  /// lives there, and duplicating it here would give appeals two homes.
  String? route() => switch (type) {
        NotificationType.moderationAction => '/settings/account-status',
        NotificationType.followRequest => '/follow-requests',
        NotificationType.newFollower ||
        NotificationType.followAccepted =>
          actorId == null ? null : '/profile/$actorId',
        NotificationType.itineraryRated =>
          entityId == null ? null : '/itineraries/$entityId/ratings',
        NotificationType.itinerarySaved =>
          entityId == null ? null : '/itineraries/$entityId',
        NotificationType.unknown => null,
      };

  /// Relative timestamp, reusing the same strings as the ratings list so the
  /// two feeds never drift apart.
  String timeAgo(AppLocalizations l10n) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 30) return l10n.timeAgoMonths((diff.inDays / 30).floor());
    if (diff.inDays > 0) return l10n.timeAgoDays(diff.inDays);
    if (diff.inHours > 0) return l10n.timeAgoHours(diff.inHours);
    if (diff.inMinutes > 0) return l10n.timeAgoMinutes(diff.inMinutes);
    return l10n.timeJustNow;
  }

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        subtype: subtype,
        createdAt: createdAt,
        read: read ?? this.read,
        actorId: actorId,
        actorUsername: actorUsername,
        actorDisplayName: actorDisplayName,
        actorAvatarUrl: actorAvatarUrl,
        entityType: entityType,
        entityId: entityId,
        entityTitle: entityTitle,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: NotificationType.fromString(json['type'] as String?),
        subtype: json['subtype'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        read: json['read'] as bool? ?? false,
        actorId: json['actor_id'] as String?,
        actorUsername: json['actor_username'] as String?,
        actorDisplayName: json['actor_display_name'] as String?,
        actorAvatarUrl: json['actor_avatar_url'] as String?,
        entityType: json['entity_type'] as String?,
        entityId: json['entity_id'] as String?,
        entityTitle: json['entity_title'] as String?,
      );
}

/// What the bell needs to know: how many, and whether anything arrived.
///
/// The two are separate signals and only one of them is the count. `unread` is
/// the number drawn on the badge. `latestAt` is the arrival signal, because a
/// count cannot be one: read a notification on another device while a new one
/// arrives and the count lands exactly where it started, silently swallowing
/// the arrival. MAX(created_at) only ever moves forward, and nothing anyone
/// reads anywhere can move it.
class NotificationBadge {
  final int unread;

  /// Newest notification's timestamp, UTC. Null when the user has none at all.
  final DateTime? latestAt;

  const NotificationBadge({required this.unread, this.latestAt});

  static const empty = NotificationBadge(unread: 0);

  /// Whether a notification arrived between [previous] and this.
  ///
  /// The single comparison the cue and the open-screen live refresh both use —
  /// written once so the two can never drift apart on the null cases.
  bool arrivedSince(NotificationBadge? previous) {
    // No baseline: a first poll has nothing to compare against, and treating it
    // as an arrival would make every cold launch sound like one.
    if (previous == null || latestAt == null) return false;
    // The user's very first notification — nothing before, something now.
    if (previous.latestAt == null) return true;
    return latestAt!.isAfter(previous.latestAt!);
  }

  factory NotificationBadge.fromJson(Map<String, dynamic> json) =>
      NotificationBadge(
        unread: json['unread_count'] as int? ?? 0,
        // toUtc: these are compared against each other across polls, so they
        // have to be anchored to the same zone.
        latestAt: DateTime.tryParse(json['latest_at'] as String? ?? '')?.toUtc(),
      );
}

/// GET /notifications — the page plus the badge, so opening the screen and
/// refreshing the bell is one call.
class NotificationsPage {
  final List<AppNotification> notifications;
  final NotificationBadge badge;

  const NotificationsPage({
    required this.notifications,
    required this.badge,
  });

  factory NotificationsPage.fromJson(Map<String, dynamic> json) =>
      NotificationsPage(
        notifications: ((json['notifications'] as List<dynamic>?) ?? const [])
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList(),
        // The feed carries the same two fields as the badge endpoint, which is
        // what lets a feed load move the arrival baseline without a second
        // request — and avoids assuming notifications[0] is newest, which only
        // holds at offset=0.
        badge: NotificationBadge.fromJson(json),
      );
}
