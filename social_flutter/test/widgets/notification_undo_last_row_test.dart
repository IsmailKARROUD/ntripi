// test/widgets/notification_undo_last_row_test.dart
//
// Dismissing the ONLY row swaps the feed for the empty view, unmounting the
// widget whose ref the undo callback read from. That read threw ("ref used
// after unmount"), the error path's context was gone too, and UNDO silently
// did nothing while the delete went through.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';
import 'package:social_flutter/features/notifications/presentation/notifications_screen.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class _Repo extends NotificationRepository {
  _Repo(this.rows) : super(Dio());

  final List<AppNotification> rows;
  final List<String> deleted = [];

  @override
  Future<NotificationsPage> getNotifications({
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async =>
      NotificationsPage(
        notifications: offset == 0 ? rows : const [],
        badge: NotificationBadge(unread: 0, latestAt: rows.first.createdAt),
      );

  @override
  Future<NotificationBadge> getBadge({bool forceRefresh = false}) async =>
      NotificationBadge(unread: 0, latestAt: rows.first.createdAt);

  @override
  Future<void> markRead({List<String>? ids}) async {}

  @override
  Future<void> deleteNotification(String id) async => deleted.add(id);
}

final _only = AppNotification(
  id: 'only',
  type: NotificationType.newFollower,
  subtype: null,
  createdAt: DateTime.utc(2026, 9, 1),
  read: true,
  actorId: 'actor',
  actorUsername: 'someone',
  actorDisplayName: 'Someone Nice',
  actorAvatarUrl: null,
  entityType: null,
  entityId: null,
  entityTitle: null,
);

void main() {
  testWidgets(
      'Given the last notification is dismissed, When UNDO is tapped, '
      'Then the row comes back and nothing is deleted', (tester) async {
    final repo = _Repo([_only]);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Someone Nice'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    // Let the snackbar finish sliding in before tapping its action.
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.textContaining('Someone Nice'), findsNothing);

    await tester.tap(find.text('UNDO'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Someone Nice'), findsOneWidget);

    // Past the undo window: the queue must be empty, not firing the DELETE.
    await tester.pump(const Duration(seconds: 10));
    expect(repo.deleted, isEmpty);
  });
}
