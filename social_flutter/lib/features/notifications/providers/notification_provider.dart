// features/notifications/providers/notification_provider.dart
//
// Feed state plus the bell badge count.
//
// The badge is its own provider rather than being derived from the feed: the
// bell is on the profile screen, where loading the whole feed just to render a
// dot would be wasted. Both are invalidated together by markAllRead.
//
// Deleting is deferred, not optimistic-with-rollback: dismiss() takes the row
// off screen and only queues the DELETE, which fires when the undo window
// closes. Undo is therefore real — nothing was sent — where a server-first
// delete could only be "undone" by re-creating a row the API cannot re-create.
//
// Both notifiers carry two reads: a user-initiated one (refresh) that may show
// a spinner and may fail loudly, and a background one (poll / silentRefresh)
// driven by NotificationPoller that may do neither. Nobody asked for the
// background read, so it must never blank a good badge or a loaded feed.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';

/// How long a dismissed row can still be brought back. The undo snackbar must
/// be shown for exactly this long or UNDO outlives the window it undoes.
const kNotificationUndoWindow = Duration(seconds: 5);

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(dio);
});

/// A row taken off screen whose DELETE has not been sent yet.
class _PendingDelete {
  final AppNotification notification;
  final Timer timer;

  const _PendingDelete(this.notification, this.timer);
}

/// The notification feed, newest first.
class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  /// Dismissed rows awaiting their DELETE, keyed by notification id.
  final Map<String, _PendingDelete> _pending = {};

  @override
  Future<List<AppNotification>> build() async {
    ref.onDispose(_cancelPending);
    final page = await ref.read(notificationRepositoryProvider).getNotifications();
    return page.notifications;
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    // Settle the queue first: a reload mid-window would re-show rows that are
    // about to be deleted anyway.
    await flushPending();
    if (!ref.mounted) return;
    // Only a state with nothing to show swaps in the skeleton. A pull-to-refresh
    // draws its own spinner over a list the user is still holding, and blanking
    // it mid-gesture reads as the feed being wiped. (AsyncValue.copyWithPrevious
    // is package-internal in Riverpod 3, so this is the supported way to say it.)
    if (!state.hasValue) state = const AsyncLoading();
    final next = await AsyncValue.guard(() async {
      final page = await ref
          .read(notificationRepositoryProvider)
          .getNotifications(forceRefresh: true);
      // The badge count rides along with every page — spending a second request
      // on what is already in hand is why pulling here never fixed the bell.
      _pushCount(page.unreadCount);
      return page.notifications;
    });
    // Assigning state on a disposed notifier throws; a pull-to-refresh the user
    // navigated away from must not take the app down with it.
    if (!ref.mounted) return;
    state = next;
  }

  /// Reload in the background, leaving the current rows on screen throughout.
  ///
  /// The poller's counterpart to [refresh]: nobody asked for this load, so it
  /// may neither blank the feed with a spinner nor replace it with an error —
  /// a failed background fetch just leaves the last good data alone.
  Future<void> silentRefresh() async {
    if (!isOnlineNowRef(ref)) return;
    // A queued DELETE means an undo snackbar is still on screen. Reloading now
    // would put the dismissed row back under the user's finger, and flushing
    // the queue first would destroy the undo they were offered. The row is
    // already gone from the server's next answer anyway — wait for the window.
    if (_pending.isNotEmpty) return;

    final List<AppNotification> rows;
    try {
      final page =
          await ref.read(notificationRepositoryProvider).getNotifications();
      if (!ref.mounted) return;
      _pushCount(page.unreadCount);
      rows = page.notifications;
    } catch (_) {
      // Swallowed on purpose — see the doc comment. The next poll retries.
      return;
    }
    if (!ref.mounted) return;
    state = AsyncData(rows);
  }

  /// Hand the badge the count that came down with the feed. Never called from
  /// [build] — writing another provider mid-build is the one thing Riverpod
  /// forbids outright, and the poller keeps the badge current regardless.
  void _pushCount(int unread) {
    if (!ref.mounted) return;
    // Only into a badge that already exists and has settled. Reading it into
    // existence here would fire the very request this exists to save, and a
    // build still in flight would overwrite what we pushed the moment its own
    // (equally fresh) answer lands.
    if (!ref.exists(unreadNotificationCountProvider)) return;
    if (ref.read(unreadNotificationCountProvider).isLoading) return;
    ref.read(unreadNotificationCountProvider.notifier).setCount(unread);
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
      // badge recovers from a write that did not land. Guarded because this
      // screen marks read from a post-frame callback, so the provider can be
      // gone by the time the call returns.
      if (ref.mounted) ref.invalidate(unreadNotificationCountProvider);
    }
  }

  /// Take a row off screen and queue its DELETE. Returns false when nothing
  /// happened, which is the caller's signal not to show the undo snackbar.
  bool dismiss(String id) {
    // Offline the queued DELETE could only fail, and the row would come back on
    // the next load — better to not pretend it went anywhere.
    if (!isOnlineNowRef(ref)) return false;

    final current = state.value;
    if (current == null || _pending.containsKey(id)) return false;

    final index = current.indexWhere((n) => n.id == id);
    if (index < 0) return false;

    final row = current[index];
    state = AsyncData([...current]..removeAt(index));
    _pending[id] = _PendingDelete(
      row,
      Timer(kNotificationUndoWindow, () => _commit(id)),
    );
    return true;
  }

  /// Put a dismissed row back. A no-op once its DELETE has been sent.
  void undoDismiss(String id) {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();

    final current = state.value;
    if (current == null) return;
    // Re-sorted rather than restored to a saved index: that index goes stale the
    // moment a second row is dismissed, and the feed is newest-first anyway.
    state = AsyncData(
      [...current, pending.notification]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  /// Send every queued DELETE now. Called when the screen closes, so leaving
  /// settles the queue instead of relying on a timer nobody is watching.
  Future<void> flushPending() async {
    final ids = _pending.keys.toList();
    for (final id in ids) {
      await _commit(id);
    }
  }

  /// Empty the feed on the server. Tier-2 confirmed by the caller.
  Future<void> clearAll() async {
    // Flush first: a queued DELETE firing afterwards is harmless (the endpoint
    // is idempotent) but it would race the state assignment below.
    await flushPending();
    await ref.read(notificationRepositoryProvider).clearAll();
    // Same post-await disposal hazard as _commit: the server call succeeded, so
    // silence is the right outcome if nobody is left to show the result to.
    if (!ref.mounted) return;
    state = const AsyncData([]);
    ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> _commit(String id) async {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();

    try {
      await ref.read(notificationRepositoryProvider).deleteNotification(id);
    } catch (_) {
      // Never rethrown: this runs from a Timer, usually after the screen that
      // could have shown a snackbar is gone, and an unhandled async error would
      // be the only result. The row reappearing IS the failure signal — leaving
      // it hidden would put the feed at odds with the next reload.
      if (!ref.mounted) return;
      final current = state.value;
      if (current != null) {
        state = AsyncData(
          [...current, pending.notification]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
      }
      return;
    }
    // The provider can be disposed across that await — logout invalidates it,
    // and a disposed Ref throws rather than quietly no-opping. The DELETE has
    // landed by here, so there is nothing left to do but skip the badge nudge.
    if (!ref.mounted) return;
    // A deleted unread row changes the badge, and this screen can be stale.
    ref.invalidate(unreadNotificationCountProvider);
  }

  void _cancelPending() {
    for (final pending in _pending.values) {
      pending.timer.cancel();
    }
    _pending.clear();
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

  /// The polled read. Returns true when the count went **up**, which is the
  /// app's only signal that something new arrived.
  ///
  /// The only read this notifier needs. There is no forced variant: the three
  /// user actions that change the count (markAllRead, clearAll, a committed
  /// delete) invalidate the provider outright, and a feed load hands its count
  /// over via [setCount] rather than asking for it again.
  ///
  /// Deliberately not forced: the conditional GET sends If-None-Match, so an
  /// unchanged count comes back 304 with no body and the cache interceptor
  /// replays the value. That is what makes a once-a-minute poll close to free.
  Future<bool> poll() async {
    if (!isOnlineNowRef(ref)) return false;

    // The very first poll lands while build() is still in flight — the poller
    // reads this notifier into existence and immediately asks it to fetch. Wait
    // for the answer already on the wire instead of racing a second request for
    // the same integer, and report no arrival: there is no baseline to rise
    // from, and a cold launch showing three unread is not three that just came.
    if (!state.hasValue) {
      try {
        await future;
      } catch (_) {
        // build()'s failure is already the provider's state; nothing to add.
      }
      return false;
    }

    final int next;
    try {
      next = await ref.read(notificationRepositoryProvider).getUnreadCount();
    } catch (_) {
      // Never written as AsyncError: nobody asked for this read, and blanking a
      // correct badge because one poll hit a dead tunnel is worse than a count
      // that is a minute stale. The next poll corrects it.
      return false;
    }
    if (!ref.mounted) return false;

    // hasValue above guarantees a real baseline here, so a rise is genuinely
    // new rather than the first number this session happened to see.
    final previous = state.value;
    state = AsyncData(next);
    return previous != null && next > previous;
  }

  /// Accept a count that arrived with a feed page instead of spending a request.
  void setCount(int unread) => state = AsyncData(unread);
}

final unreadNotificationCountProvider =
    AsyncNotifierProvider<UnreadNotificationCountNotifier, int>(
  () => UnreadNotificationCountNotifier(),
);
