// features/notifications/providers/notification_provider.dart
//
// Feed state plus the bell badge count.
//
// The badge is its own provider rather than being derived from the feed: the
// bell is on the profile screen, where loading the whole feed just to render a
// dot would be wasted. Both are invalidated together by markAllRead.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(dio);
});

/// The notification feed, newest first.
class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final page = await ref.read(notificationRepositoryProvider).getNotifications();
    return page.notifications;
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final page = await ref
          .read(notificationRepositoryProvider)
          .getNotifications(forceRefresh: true);
      return page.notifications;
    });
  }

  /// Clear the badge on the server, leaving the rows on screen as they are.
  ///
  /// Deliberately NOT optimistic: flipping the local rows to read would erase
  /// the unread tint in the same frame the user arrived to look at it. The
  /// badge is what they came to clear; which rows were new is what they came to
  /// see. The next load returns them read.
  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null || current.every((n) => n.read)) return;

    try {
      await ref.read(notificationRepositoryProvider).markRead();
    } finally {
      // Even on failure: the server is the authority, and re-reading is how the
      // badge recovers from a write that did not land.
      ref.invalidate(unreadNotificationCountProvider);
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(
  () => NotificationsNotifier(),
);

/// Badge count for the bell. Kept separate from the feed so the profile screen
/// does not have to load the list to draw a dot.
class UnreadNotificationCountNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() {
    return ref.read(notificationRepositoryProvider).getUnreadCount();
  }

  Future<void> refresh() async {
    if (!isOnlineNowRef(ref)) return;
    state = await AsyncValue.guard(
      () => ref
          .read(notificationRepositoryProvider)
          .getUnreadCount(forceRefresh: true),
    );
  }
}

final unreadNotificationCountProvider =
    AsyncNotifierProvider<UnreadNotificationCountNotifier, int>(
  () => UnreadNotificationCountNotifier(),
);
