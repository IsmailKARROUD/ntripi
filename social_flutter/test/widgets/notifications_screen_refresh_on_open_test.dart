// test/widgets/notifications_screen_refresh_on_open_test.dart
//
// notificationsProvider is keep-alive, so the screen's second visit renders
// whatever the first visit fetched. That is not merely stale here, because the
// screen also marks the feed read on open, and the server is the authority on
// read state: marking a *cached* feed read marks a row the user has never been
// shown read, clears the badge for it, and leaves nothing anywhere to surface
// it as new again. The notification is consumed without ever being displayed.
//
// The fix is ordering — refresh, then act — so these tests assert the order,
// not just the outcome.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/features/notifications/presentation/notifications_screen.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

/// Records every call in order, which is the whole assertion here.
class _RecordingRepo extends NotificationRepository {
  _RecordingRepo({required this.rows}) : super(Dio());

  /// Swapped mid-test to stand in for a notification arriving server-side.
  List<AppNotification> rows;

  final List<String> calls = [];
  bool failFeed = false;

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    calls.add('feed');
    if (failFeed) throw DioException(requestOptions: RequestOptions());
    return NotificationsPage(
      notifications: rows,
      badge: NotificationBadge(unread: rows.length, latestAt: _t1),
    );
  }

  @override
  Future<NotificationBadge> getBadge({bool forceRefresh = false}) async {
    calls.add('badge');
    return NotificationBadge(unread: rows.length, latestAt: _t1);
  }

  @override
  Future<void> markRead({List<String>? ids}) async => calls.add('markRead');

  @override
  Future<void> deleteNotification(String id) async {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────

final _t1 = DateTime.utc(2026, 8, 3, 10);

AppNotification _notification(String id, DateTime createdAt) => AppNotification(
      id: id,
      type: NotificationType.newFollower,
      subtype: null,
      createdAt: createdAt,
      read: false,
      actorId: 'actor-$id',
      actorUsername: id,
      actorDisplayName: 'Actor $id',
      actorAvatarUrl: null,
      entityType: null,
      entityId: null,
      entityTitle: null,
    );

final _old = _notification('n1', DateTime.utc(2026, 8, 1));
final _fresh = _notification('n2', DateTime.utc(2026, 8, 3));

ProviderContainer _container(_RecordingRepo repo) => ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );

/// The container is passed in rather than created per-pump, because the bug
/// under test only exists while provider state OUTLIVES the screen — a fresh
/// ProviderScope would rebuild notificationsProvider and fetch cleanly, hiding
/// exactly the staleness these tests exist to catch.
Widget _screen(ProviderContainer container, {bool showScreen = true}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: showScreen ? const NotificationsScreen() : const SizedBox.shrink(),
      ),
    );

/// Leave the screen and come back, with the provider container left standing.
Future<void> _reopen(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(_screen(container, showScreen: false));
  await tester.pump();
  await tester.pumpWidget(_screen(container));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
      'Given a notification arrived since the feed was last loaded, '
      'When the screen is opened, '
      'Then it is refetched and rendered before anything is marked read',
      (tester) async {
    final repo = _RecordingRepo(rows: [_old]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    // One arrives while the user is elsewhere.
    repo.rows = [_fresh, _old];
    repo.calls.clear();

    // Reopening the screen: a fresh State over the same keep-alive provider,
    // which is exactly the situation that used to render the cached list.
    await _reopen(tester, container);

    expect(find.textContaining('Actor n2'), findsOneWidget);
    // Both must have happened — indexOf returns -1 for a missing call, so
    // asserting the order alone would pass vacuously if the feed was never
    // refetched, which is precisely the bug under test.
    expect(repo.calls, contains('feed'));
    expect(repo.calls, contains('markRead'));
    // The order is the bug. markRead against the cached feed would have marked
    // n2 read on the server while it was still invisible.
    expect(repo.calls.indexOf('feed'), lessThan(repo.calls.indexOf('markRead')));
  });

  testWidgets(
      'Given the feed has never loaded successfully, '
      'When the screen is opened, '
      'Then nothing is marked read', (tester) async {
    final repo = _RecordingRepo(rows: [_old])..failFeed = true;
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    // Clearing the badge over a feed the user was never shown would strand the
    // rows: cleared bell, nothing on screen, no second chance.
    expect(repo.calls, isNot(contains('markRead')));
  });

  testWidgets(
      'Given the screen is open, '
      'When a poll reports an arrival, '
      'Then the new row is pulled in without the user asking', (tester) async {
    final repo = _RecordingRepo(rows: [_old]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();
    expect(find.textContaining('Actor n2'), findsNothing);

    // What the poller does: it only maintains the badge, and the screen listens
    // for the arrival. Pushed with a later timestamp so arrivedSince fires.
    repo.rows = [_fresh, _old];
    container.read(notificationBadgeProvider.notifier).setBadge(
          NotificationBadge(unread: 2, latestAt: _t1.add(const Duration(hours: 1))),
        );
    await tester.pumpAndSettle();

    expect(find.textContaining('Actor n2'), findsOneWidget);
  });
}
