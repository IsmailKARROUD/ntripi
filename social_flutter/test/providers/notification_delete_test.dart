// test/providers/notification_delete_test.dart — the deferred-delete queue.
//
// Deleting a notification is not a server-first write with a rollback: dismiss()
// only takes the row off screen and queues the DELETE, which fires when the undo
// window closes. That is what makes UNDO real — the API cannot re-create a row,
// so an "undo" after the request had already gone would be a lie.
//
// These tests pin the three things that property depends on: nothing is sent
// inside the window, undo cancels the send outright, and leaving the screen
// (flushPending) settles the queue instead of waiting on a timer.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeNotificationRepo extends NotificationRepository {
  _FakeNotificationRepo({this.failDelete = false}) : super(Dio());

  final bool failDelete;
  final List<String> deleted = [];
  int clearAllCalls = 0;

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    return NotificationsPage(notifications: _feed(), unreadCount: 3);
  }

  @override
  Future<int> getUnreadCount({bool forceRefresh = false}) async => 3;

  @override
  Future<void> deleteNotification(String id) async {
    if (failDelete) throw DioException(requestOptions: RequestOptions());
    deleted.add(id);
  }

  @override
  Future<void> clearAll() async => clearAllCalls++;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AppNotification _notification(String id, DateTime createdAt) => AppNotification(
      id: id,
      type: NotificationType.newFollower,
      subtype: null,
      createdAt: createdAt,
      read: false,
      actorId: 'actor-$id',
      actorUsername: 'actor',
      actorDisplayName: 'Actor',
      actorAvatarUrl: null,
      entityType: null,
      entityId: null,
      entityTitle: null,
    );

/// Newest first, matching the server's ORDER BY created_at DESC.
List<AppNotification> _feed() => [
      _notification('n1', DateTime.utc(2026, 8, 3)),
      _notification('n2', DateTime.utc(2026, 8, 2)),
      _notification('n3', DateTime.utc(2026, 8, 1)),
    ];

ProviderContainer _makeContainer(
  _FakeNotificationRepo repo, {
  bool online = true,
}) {
  return ProviderContainer(overrides: [
    notificationRepositoryProvider.overrideWithValue(repo),
    isOnlineProvider.overrideWith((ref) => Stream.value(online)),
  ]);
}

/// StreamProviders only consume their stream while actively listened, so the
/// sync isOnlineNowRef read would otherwise see the optimistic pre-seed default.
Future<void> _settleConnectivity(ProviderContainer container) async {
  final sub = container.listen(isOnlineProvider, (_, _) {});
  addTearDown(sub.close);
  await container.read(isOnlineProvider.future);
}

List<String> _ids(ProviderContainer container) =>
    container.read(notificationsProvider).value!.map((n) => n.id).toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('NotificationsNotifier deferred delete', () {
    test(
        'Given a loaded feed, '
        'When dismiss() is called, '
        'Then the row leaves the state and nothing is sent yet', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      expect(container.read(notificationsProvider.notifier).dismiss('n2'), isTrue);

      expect(_ids(container), ['n1', 'n3']);
      // The whole point of the window: no request until it closes.
      expect(repo.deleted, isEmpty);
    });

    test(
        'Given a dismissed row, '
        'When undoDismiss() runs inside the window, '
        'Then it is restored newest-first and never sent', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final notifier = container.read(notificationsProvider.notifier);
      notifier.dismiss('n2');
      notifier.undoDismiss('n2');

      // Re-sorted, not appended — a saved index goes stale the moment a second
      // row is dismissed.
      expect(_ids(container), ['n1', 'n2', 'n3']);
      expect(repo.deleted, isEmpty);
    });

    test(
        'Given two dismissed rows, '
        'When only the older one is undone, '
        'Then it lands back in place and the other still commits', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final notifier = container.read(notificationsProvider.notifier);
      notifier.dismiss('n1');
      notifier.dismiss('n3');
      notifier.undoDismiss('n3');
      await notifier.flushPending();

      expect(_ids(container), ['n2', 'n3']);
      expect(repo.deleted, ['n1']);
    });

    test(
        'Given a dismissed row, '
        'When flushPending() runs, '
        'Then the DELETE is sent without waiting for the timer', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final notifier = container.read(notificationsProvider.notifier);
      notifier.dismiss('n2');
      await notifier.flushPending();

      expect(repo.deleted, ['n2']);
      // Already committed: undo is now a no-op, not a resurrection.
      notifier.undoDismiss('n2');
      expect(_ids(container), ['n1', 'n3']);
    });

    testWidgets(
        'Given a dismissed row nobody undid, '
        'When the undo window elapses, '
        'Then the DELETE fires on its own', (tester) async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      final sub = container.listen(isOnlineProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(isOnlineProvider.future);

      container.read(notificationsProvider.notifier).dismiss('n2');
      expect(repo.deleted, isEmpty);

      // testWidgets fakes the clock, so this advances the queued Timer.
      await tester.pump(kNotificationUndoWindow);
      await tester.pump();

      expect(repo.deleted, ['n2']);
    });

    test(
        'Given the DELETE fails, '
        'When the queue is flushed, '
        'Then the row comes back rather than silently vanishing', () async {
      final repo = _FakeNotificationRepo(failDelete: true);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final notifier = container.read(notificationsProvider.notifier);
      notifier.dismiss('n2');
      // Must not rethrow: this also runs from a Timer, where an unhandled async
      // error would be the only outcome.
      await notifier.flushPending();

      expect(_ids(container), ['n1', 'n2', 'n3']);
    });

    test(
        'Given the device is offline, '
        'When dismiss() is called, '
        'Then it refuses and the feed is untouched', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo, online: false);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      // false is the screen's signal not to show an undo snackbar for a delete
      // that could only fail and resurrect the row on the next load.
      expect(
        container.read(notificationsProvider.notifier).dismiss('n2'),
        isFalse,
      );
      expect(_ids(container), ['n1', 'n2', 'n3']);
      expect(repo.deleted, isEmpty);
    });

    test(
        'Given a pending delete, '
        'When clearAll() runs, '
        'Then the queue is flushed first and the feed empties', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final notifier = container.read(notificationsProvider.notifier);
      notifier.dismiss('n2');
      await notifier.clearAll();

      expect(repo.deleted, ['n2']);
      expect(repo.clearAllCalls, 1);
      expect(_ids(container), isEmpty);
    });
  });
}
