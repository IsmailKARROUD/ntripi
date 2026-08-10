// test/widgets/notifications_screen_teardown_test.dart
//
// The screen flushes its pending-delete queue when it is torn down. Doing that
// through the widget `ref` throws in Riverpod 3 ("Using ref when a widget is
// about to or has been unmounted is unsafe") — and the screen can be torn down
// by a redirect the user never asked for, so the crash lands on someone who
// merely walked away from the feed.
//
// These tests pin both halves: teardown must not throw, and the queued DELETE
// must still be sent on the way out.

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

class _FakeNotificationRepo extends NotificationRepository {
  _FakeNotificationRepo() : super(Dio());

  final List<String> deleted = [];

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async =>
      NotificationsPage(notifications: _feed(), unreadCount: 2);

  @override
  Future<int> getUnreadCount({bool forceRefresh = false}) async => 2;

  @override
  Future<void> markRead({List<String>? ids}) async {}

  @override
  Future<void> deleteNotification(String id) async => deleted.add(id);

  @override
  Future<void> clearAll() async {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────

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
    ];

Widget _buildScreen(_FakeNotificationRepo repo) => ProviderScope(
      // Matches the app root: Riverpod 3 auto-retry would mask a thrown error.
      retry: (_, _) => null,
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationsScreen(),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('NotificationsScreen teardown', () {
    testWidgets(
        'Given the screen is open with nothing dismissed, '
        'When it is unmounted, '
        'Then dispose does not touch ref and nothing throws', (tester) async {
      final repo = _FakeNotificationRepo();
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pumpAndSettle();

      // The teardown a redirect causes: the screen goes away mid-session.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Given a row was dismissed, '
        'When the screen is unmounted inside the undo window, '
        'Then the queued DELETE is still sent and nothing throws',
        (tester) async {
      final repo = _FakeNotificationRepo();
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();
      // Still inside the window — the timer has not fired.
      expect(repo.deleted, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(repo.deleted, ['n1']);
    });
  });
}
