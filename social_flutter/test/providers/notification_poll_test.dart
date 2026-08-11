// test/providers/notification_poll_test.dart — the background reads.
//
// There is no push channel, so NotificationPoller asks once a minute. That makes
// these reads unlike every other one in the app: nobody requested them, and they
// land on top of whatever the user is currently looking at.
//
// Everything below pins the same property from a different angle — a background
// read may improve the state and may never degrade it. A failed poll must not
// blank a correct badge, a failed silent refresh must not blank a loaded feed,
// and neither may resurrect a row sitting inside its undo window.

import 'dart:async';

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
  _FakeNotificationRepo({
    this.counts = const [0],
    this.feedUnreadCount = 0,
  }) : super(Dio());

  /// Consumed one per call; the last entry repeats once exhausted.
  final List<int> counts;

  /// Flipped mid-test so a repo can load cleanly and *then* start refusing —
  /// the only interesting case, since a background read is judged by what it
  /// does to state that is already good.
  bool failCount = false;
  bool failFeed = false;

  /// What `unread_count` the feed page carries — the badge value that already
  /// rides along with every list response.
  final int feedUnreadCount;

  int countCalls = 0;
  int feedCalls = 0;

  /// When set, getNotifications parks until it completes, so a test can inspect
  /// the state mid-flight.
  Completer<void>? feedGate;

  @override
  Future<int> getUnreadCount({bool forceRefresh = false}) async {
    countCalls++;
    if (failCount) throw DioException(requestOptions: RequestOptions());
    final index = countCalls - 1;
    return counts[index < counts.length ? index : counts.length - 1];
  }

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    feedCalls++;
    if (feedGate != null) await feedGate!.future;
    if (failFeed) throw DioException(requestOptions: RequestOptions());
    return NotificationsPage(
      notifications: _feed(),
      unreadCount: feedUnreadCount,
    );
  }

  @override
  Future<void> deleteNotification(String id) async {}
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
  group('UnreadNotificationCountNotifier.poll', () {
    test(
        'Given the badge has not loaded yet, '
        'When poll() runs, '
        'Then it waits for build() instead of racing a second request', () async {
      final repo = _FakeNotificationRepo(counts: [3]);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);
      await _settleConnectivity(container);

      // Exactly what the poller does at launch: read the notifier into
      // existence and immediately ask it to fetch.
      final notifier = container.read(unreadNotificationCountProvider.notifier);
      final arrived = await notifier.poll();

      // No baseline to rise from — a cold launch showing 3 unread is not 3 that
      // just came in, and ringing the cue there would be wrong every time.
      expect(arrived, isFalse);
      expect(container.read(unreadNotificationCountProvider).value, 3);
      // The whole point: one request for one integer, not two.
      expect(repo.countCalls, 1);
    });

    test(
        'Given a loaded badge, '
        'When the count rises, '
        'Then poll() reports an arrival and stores the new value', () async {
      final repo = _FakeNotificationRepo(counts: [1, 4]);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);
      await _settleConnectivity(container);

      await container.read(unreadNotificationCountProvider.future);
      final arrived =
          await container.read(unreadNotificationCountProvider.notifier).poll();

      expect(arrived, isTrue);
      expect(container.read(unreadNotificationCountProvider).value, 4);
    });

    test(
        'Given a loaded badge, '
        'When the count is unchanged or drops, '
        'Then poll() reports no arrival', () async {
      // 2 → 2 (a 304 replay) → 1 (read on another device).
      final repo = _FakeNotificationRepo(counts: [2, 2, 1]);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);
      await _settleConnectivity(container);

      await container.read(unreadNotificationCountProvider.future);
      final notifier = container.read(unreadNotificationCountProvider.notifier);

      expect(await notifier.poll(), isFalse);
      expect(await notifier.poll(), isFalse);
      // A drop is still stored — that is the badge correcting itself after the
      // user read something somewhere else.
      expect(container.read(unreadNotificationCountProvider).value, 1);
    });

    test(
        'Given a loaded badge, '
        'When the poll request fails, '
        'Then the last good count survives and no error is published', () async {
      final repo = _FakeNotificationRepo(counts: [5]);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);
      await _settleConnectivity(container);

      await container.read(unreadNotificationCountProvider.future);
      final notifier = container.read(unreadNotificationCountProvider.notifier);

      // The tunnel dies after the badge is already correct.
      repo.failCount = true;

      expect(await notifier.poll(), isFalse);
      expect(container.read(unreadNotificationCountProvider).value, 5);
      expect(container.read(unreadNotificationCountProvider).hasError, isFalse);
    });

    test(
        'Given the device is offline, '
        'When poll() runs, '
        'Then nothing is requested at all', () async {
      final repo = _FakeNotificationRepo(counts: [7]);
      final container = _makeContainer(repo, online: false);
      addTearDown(container.dispose);
      await _settleConnectivity(container);

      final notifier = container.read(unreadNotificationCountProvider.notifier);
      // build() still ran, but poll() itself must not add a request.
      final before = repo.countCalls;
      expect(await notifier.poll(), isFalse);
      expect(repo.countCalls, before);
    });
  });

  group('NotificationsNotifier.silentRefresh', () {
    test(
        'Given a row is inside its undo window, '
        'When silentRefresh() runs, '
        'Then it declines rather than resurrecting the row', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final notifier = container.read(notificationsProvider.notifier);
      notifier.dismiss('n2');
      final feedCallsBefore = repo.feedCalls;

      await notifier.silentRefresh();

      // Putting n2 back under the user's finger would be bad; flushing the queue
      // first to avoid that would silently destroy the undo they were offered.
      expect(_ids(container), ['n1', 'n3']);
      expect(repo.feedCalls, feedCallsBefore);
    });

    test(
        'Given a loaded feed, '
        'When the silent request fails, '
        'Then the rows stay put and no error reaches the screen', () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      repo.failFeed = true;

      // Nobody asked for this read — a spinner or an error page would be the
      // app interrupting the user with news about a request they never made.
      await container.read(notificationsProvider.notifier).silentRefresh();

      expect(_ids(container), ['n1', 'n2', 'n3']);
      expect(container.read(notificationsProvider).hasError, isFalse);
    });

    test(
        'Given a settled badge, '
        'When a feed load carries a new unread count, '
        'Then the badge takes it without spending a request', () async {
      final repo = _FakeNotificationRepo(counts: [0], feedUnreadCount: 6);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await container.read(unreadNotificationCountProvider.future);
      await _settleConnectivity(container);

      final countCallsBefore = repo.countCalls;
      await container.read(notificationsProvider.notifier).silentRefresh();

      expect(container.read(unreadNotificationCountProvider).value, 6);
      // The count rode along with the page — asking again for what is already
      // in hand is exactly the waste this avoids.
      expect(repo.countCalls, countCallsBefore);
    });
  });

  group('NotificationsNotifier.refresh', () {
    test(
        'Given a loaded feed, '
        'When a pull-to-refresh is in flight, '
        'Then the rows stay on screen instead of blanking to a skeleton',
        () async {
      final repo = _FakeNotificationRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await _settleConnectivity(container);

      final gate = Completer<void>();
      repo.feedGate = gate;
      final pending = container.read(notificationsProvider.notifier).refresh();
      // Let refresh() get past flushPending() and into the parked request.
      await Future<void>.delayed(Duration.zero);

      // RefreshIndicator draws its own spinner over a list the user is still
      // holding; swapping it for a skeleton reads as the feed being wiped.
      expect(container.read(notificationsProvider).hasValue, isTrue);
      expect(_ids(container), ['n1', 'n2', 'n3']);

      gate.complete();
      await pending;
      expect(_ids(container), ['n1', 'n2', 'n3']);
    });

    test(
        'Given a settled badge, '
        'When refresh() completes, '
        'Then the badge takes the count that came with the page', () async {
      final repo = _FakeNotificationRepo(counts: [0], feedUnreadCount: 2);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.future);
      await container.read(unreadNotificationCountProvider.future);
      await _settleConnectivity(container);

      await container.read(notificationsProvider.notifier).refresh();

      // Pulling on the feed used to leave the bell stale — the count was in the
      // response all along and was being thrown away.
      expect(container.read(unreadNotificationCountProvider).value, 2);
    });
  });
}
