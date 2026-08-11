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
import 'package:social_flutter/shared/widgets/loaders.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeNotificationRepo extends NotificationRepository {
  _FakeNotificationRepo({this.clearAllGate}) : super(Dio());

  /// Held open by a test that needs to observe the in-flight state.
  final Completer<void>? clearAllGate;
  final List<String> deleted = [];
  int clearAllCalls = 0;

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async => NotificationsPage(
        notifications: _feed(),
        badge: const NotificationBadge(unread: 2),
      );

  @override
  Future<NotificationBadge> getBadge({bool forceRefresh = false}) async =>
      const NotificationBadge(unread: 2);

  @override
  Future<void> markRead({List<String>? ids}) async {}

  @override
  Future<void> deleteNotification(String id) async => deleted.add(id);

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
    await clearAllGate?.future;
  }
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

  group('NotificationsScreen clear all', () {
    testWidgets(
        'Given the confirm dialog was accepted, '
        'When the request is still in flight, '
        'Then the button shows the Ntripi ring loader and cannot be re-tapped',
        (tester) async {
      final gate = Completer<void>();
      final repo = _FakeNotificationRepo(clearAllGate: gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await tester.pumpWidget(_buildScreen(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.text(l10n.notificationsClearAll));
      await tester.pumpAndSettle();
      // Tier 2 confirm first — the loader must not appear before the user says
      // yes, and the confirm label matches the button's, hence .last.
      expect(find.byType(NTripiRingLoader), findsNothing);

      await tester.tap(find.text(l10n.notificationsClearAll).last);
      await tester.pump();
      // Fixed pump, not pumpAndSettle: the dialog's exit transition has to
      // finish (its icon is also backspace_outlined) but the ring loader spins
      // forever, so settling would time out.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(NTripiRingLoader), findsOneWidget);
      // The backspace icon gave up its slot, so the label still reads.
      expect(find.byIcon(Icons.backspace_outlined), findsNothing);
      expect(find.text(l10n.notificationsClearAll), findsOneWidget);

      // Re-tapping while in flight must not fire a second request.
      await tester.tap(find.text(l10n.notificationsClearAll));
      await tester.pump();
      expect(repo.clearAllCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();

      // Feed emptied: the loader is gone along with the whole button.
      expect(find.byType(NTripiRingLoader), findsNothing);
      expect(find.text(l10n.notificationsEmpty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
