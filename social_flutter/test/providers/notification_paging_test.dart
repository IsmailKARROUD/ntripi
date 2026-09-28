// test/providers/notification_paging_test.dart
//
// The feed used to load one page and stop, while markAllRead() posted no ids —
// which the server reads as "every unread row". Rows past the first page, or
// ones that arrived between the reload and the POST, were marked read without
// ever being shown, and a row marked read unseen never surfaces as new again.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';

class _PagingRepo extends NotificationRepository {
  _PagingRepo(this.rows) : super(Dio());

  /// Newest first, like the server.
  List<AppNotification> rows;
  final List<List<String>?> markReadCalls = [];
  final List<int> offsets = [];

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    offsets.add(offset);
    return NotificationsPage(
      notifications: rows.skip(offset).take(limit).toList(),
      badge: NotificationBadge(unread: rows.length, latestAt: rows.first.createdAt),
    );
  }

  @override
  Future<NotificationBadge> getBadge({bool forceRefresh = false}) async =>
      NotificationBadge(unread: rows.length, latestAt: rows.first.createdAt);

  @override
  Future<void> markRead({List<String>? ids}) async => markReadCalls.add(ids);
}

AppNotification _row(int i) => AppNotification(
      id: 'n$i',
      type: NotificationType.newFollower,
      subtype: null,
      // i = 0 is the newest.
      createdAt: DateTime.utc(2026, 9, 1).subtract(Duration(minutes: i)),
      read: false,
      actorId: 'a$i',
      actorUsername: 'a$i',
      actorDisplayName: null,
      actorAvatarUrl: null,
      entityType: null,
      entityId: null,
      entityTitle: null,
    );

ProviderContainer _container(_PagingRepo repo) => ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );

void main() {
  test(
      'Given more unread rows than one page, When the loaded feed is marked read, '
      'Then only the rows actually loaded are named', () async {
    final repo = _PagingRepo([for (var i = 0; i < 45; i++) _row(i)]);
    final container = _container(repo);
    addTearDown(container.dispose);

    final loaded = await container.read(notificationsProvider.future);
    expect(loaded, hasLength(kNotificationPageSize));

    await container.read(notificationsProvider.notifier).markAllRead();

    expect(repo.markReadCalls, hasLength(1));
    expect(repo.markReadCalls.single, [for (var i = 0; i < 30; i++) 'n$i']);
  });

  test(
      'Given a full first page, When more is loaded, '
      'Then the next page is appended and its rows are marked read by id', () async {
    final repo = _PagingRepo([for (var i = 0; i < 45; i++) _row(i)]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await container.read(notificationsProvider.future);
    final notifier = container.read(notificationsProvider.notifier);
    expect(notifier.hasMore, isTrue);

    await notifier.loadMore();

    final rows = container.read(notificationsProvider).value!;
    expect(rows, hasLength(45));
    expect(repo.offsets.last, 30);
    expect(notifier.hasMore, isFalse);
    expect(repo.markReadCalls.single, [for (var i = 30; i < 45; i++) 'n$i']);
  });

  test(
      'Given an arrival between pages, When more is loaded, '
      'Then the row pushed across the boundary is not shown twice', () async {
    final repo = _PagingRepo([for (var i = 0; i < 45; i++) _row(i)]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await container.read(notificationsProvider.future);

    // One arrives: every row shifts down one, so offset 30 now starts at n29.
    repo.rows = [_row(-1), ...repo.rows];
    await container.read(notificationsProvider.notifier).loadMore();

    final ids = container.read(notificationsProvider).value!.map((n) => n.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });
}
