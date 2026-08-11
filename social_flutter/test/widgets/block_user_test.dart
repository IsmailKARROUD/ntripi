// test/widgets/block_user_test.dart
//
// The block flow in ugc_actions.dart. The interesting case is the async gap:
// confirmAndBlock awaits a confirm dialog and then a network POST, and only
// then touches `ref` and calls back into the caller. If the user leaves the
// screen while the POST is in flight, that work runs against a disposed
// WidgetRef / unmounted context.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/reports/data/report_repository.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/features/reports/presentation/ugc_actions.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

/// Repository whose block() completes only when the test says so, so the
/// widget can be torn down mid-request.
class _SlowBlockRepository implements ReportRepository {
  final Completer<void> gate = Completer<void>();
  bool called = false;
  bool unblockCalled = false;

  /// Seeded so blockedUserIdsProvider reports the user as already blocked.
  final List<User> blocked;

  _SlowBlockRepository({this.blocked = const []});

  @override
  Future<void> block(String userId) {
    called = true;
    return gate.future;
  }

  @override
  Future<void> unblock(String userId) async {
    unblockCalled = true;
  }

  @override
  Future<List<User>> blockedUsers() async => blocked;

  @override
  Future<void> report({
    required Object target,
    required String reason,
    String? notes,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({
  required ReportRepository repo,
  required GlobalKey<NavigatorState> navKey,
  VoidCallback? onBlocked,
}) {
  return ProviderScope(
    overrides: [reportRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      navigatorKey: navKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => confirmAndBlock(
              context,
              ref,
              userId: 'u-1',
              username: 'aminad',
              onBlocked: onBlocked,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

User _blockedUser() => User(
      id: 'u-1',
      username: 'aminad',
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      isFollowing: false,
      followIsPending: false,
      createdAt: DateTime(2025),
    );

/// Hosts the real menu widget, which is what decides Block vs Unblock.
Widget _menuHost({
  required ReportRepository repo,
  VoidCallback? onUnblocked,
}) {
  return ProviderScope(
    overrides: [reportRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: UgcActionsMenu(
          target: ReportTarget.user('u-1'),
          authorUserId: 'u-1',
          authorUsername: 'aminad',
          onUnblocked: onUnblocked,
        ),
      ),
    ),
  );
}

void main() {
  group('the menu reflects block state', () {
    testWidgets(
        'Given the user is not blocked, When the menu opens, '
        'Then it offers Block', (tester) async {
      await tester.pumpWidget(_menuHost(repo: _SlowBlockRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UgcActionsMenu));
      await tester.pumpAndSettle();

      expect(find.text('Block'), findsOneWidget);
      expect(find.text('Unblock'), findsNothing);
    });

    testWidgets(
        'Given the user is already blocked, When the menu opens, '
        'Then it offers Unblock instead', (tester) async {
      await tester.pumpWidget(_menuHost(
        repo: _SlowBlockRepository(blocked: [_blockedUser()]),
      ));
      // Settle so blockedUsersProvider resolves before the menu is read.
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UgcActionsMenu));
      await tester.pumpAndSettle();

      expect(find.text('Unblock'), findsOneWidget);
      // Offering both would let someone block an account they already blocked.
      expect(find.text('Block'), findsNothing);
    });

    testWidgets(
        'Given the user is already blocked, When Unblock is chosen, '
        'Then it unblocks without a confirm dialog', (tester) async {
      final repo = _SlowBlockRepository(blocked: [_blockedUser()]);
      var unblockedRan = false;

      await tester.pumpWidget(
          _menuHost(repo: repo, onUnblocked: () => unblockedRan = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(UgcActionsMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();

      expect(repo.unblockCalled, isTrue);
      expect(repo.called, isFalse, reason: 'must not block instead');
      expect(unblockedRan, isTrue);
      expect(find.text('Unblocked @aminad.'), findsOneWidget);
    });
  });

  group('confirmAndBlock', () {
    testWidgets(
        'Given the confirm dialog, When Cancel is chosen, '
        'Then no block request is sent', (tester) async {
      final repo = _SlowBlockRepository();
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(_host(repo: repo, navKey: navKey));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Block @aminad?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.called, isFalse);
    });

    testWidgets(
        'Given a block in flight, When the screen is disposed before it '
        'resolves, Then nothing throws', (tester) async {
      final repo = _SlowBlockRepository();
      final navKey = GlobalKey<NavigatorState>();
      var onBlockedRan = false;

      await tester.pumpWidget(_host(
        repo: repo,
        navKey: navKey,
        onBlocked: () => onBlockedRan = true,
      ));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pump();

      expect(repo.called, isTrue);

      // The user leaves while the POST is still in flight.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      // Now the request lands against a disposed ref / unmounted context.
      repo.gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(onBlockedRan, isFalse,
          reason: 'the caller must not be invoked after disposal');
    });

    testWidgets(
        'Given the screen is still mounted, When the block resolves, '
        'Then the caller is notified and the user is told', (tester) async {
      final repo = _SlowBlockRepository();
      final navKey = GlobalKey<NavigatorState>();
      var onBlockedRan = false;

      await tester.pumpWidget(_host(
        repo: repo,
        navKey: navKey,
        onBlocked: () => onBlockedRan = true,
      ));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pump();

      repo.gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(onBlockedRan, isTrue);
      expect(find.text('Blocked @aminad.'), findsOneWidget);
    });
  });
}
