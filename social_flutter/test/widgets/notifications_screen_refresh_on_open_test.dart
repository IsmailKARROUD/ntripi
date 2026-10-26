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
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/notifications/data/notification_repository.dart';
import 'package:ntripi/features/notifications/domain/app_notification.dart';
import 'package:ntripi/features/notifications/presentation/notifications_screen.dart';
import 'package:ntripi/features/notifications/providers/notification_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

/// Records every call in order, which is the whole assertion here.
class _RecordingRepo extends NotificationRepository {
  _RecordingRepo({required this.rows}) : super(Dio());

  /// Swapped mid-test to stand in for a notification arriving server-side.
  List<AppNotification> rows;

  final List<String> calls = [];
  bool failFeed = false;

  /// Held open by a test that needs to observe the in-flight state.
  Completer<void>? feedGate;

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    calls.add('feed');
    if (feedGate != null) await feedGate!.future;
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
      'Given the screen is reopened over a cached feed, '
      'When the refetch is in flight, '
      'Then a progress line shows and the cached rows stay visible',
      (tester) async {
    final repo = _RecordingRepo(rows: [_old]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    // Idle: the divider is a plain hairline, nothing spinning.
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    repo.feedGate = gate;

    await tester.pumpWidget(_screen(container, showScreen: false));
    await tester.pump();
    await tester.pumpWidget(_screen(container));
    // Fixed pumps, not pumpAndSettle: the request is parked and the indicator
    // animates forever, so settling would time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // The whole point of the silent reload — the user keeps reading meanwhile.
    expect(find.textContaining('Actor n1'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
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

  // A pull and Retry are the reads the user asks for — the loud ones. A failure
  // with rows on screen keeps them and says why; with nothing on screen, the
  // error view is the answer.
  group('a reload the user asks for', () {
    Future<void> pull(WidgetTester tester) async {
      await tester.fling(
          find.byType(RefreshIndicator), const Offset(0, 320), 1000);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'Given a loaded feed, When a pull fails, '
        'Then the rows stay and the reason shows in a SnackBar',
        (tester) async {
      final repo = _RecordingRepo(rows: [_old]);
      final container = _container(repo);
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.pumpAndSettle();

      repo.failFeed = true;
      await pull(tester);

      expect(find.textContaining('Actor n1'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('An error occurred. Please try again.'), findsOneWidget);
    });

    testWidgets(
        'Given an empty feed, When it is pulled, '
        'Then a notification that arrived shows', (tester) async {
      final repo = _RecordingRepo(rows: []);
      final container = _container(repo);
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.pumpAndSettle();

      repo.rows = [_fresh];
      await pull(tester);

      expect(find.textContaining('Actor n2'), findsOneWidget);
    });

    testWidgets(
        'Given the feed failed to load, When Retry is tapped, '
        'Then the rows load in place of the error', (tester) async {
      final repo = _RecordingRepo(rows: [_old])..failFeed = true;
      final container = _container(repo);
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.pumpAndSettle();

      repo.failFeed = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Actor n1'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Given the feed failed to load, When the error is pulled down, '
        'Then the rows load', (tester) async {
      final repo = _RecordingRepo(rows: [_old])..failFeed = true;
      final container = _container(repo);
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.pumpAndSettle();

      repo.failFeed = false;
      await pull(tester);

      expect(find.textContaining('Actor n1'), findsOneWidget);
    });
  });
}
