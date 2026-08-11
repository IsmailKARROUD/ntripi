// test/widgets/profile_settings_sheet_follow_requests_test.dart
//
// The settings sheet's Follow requests row, which sits directly above Blocked
// accounts. Two rules are worth pinning:
//   · it is drawn only for a private account — a public one auto-accepts every
//     follow, so the row could only ever open an empty screen, and the sheet
//     must not even read followRequestsProvider in that case;
//   · the pending count renders in the row's detail slot, and 0 renders as
//     nothing rather than a "0".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_settings_sheet.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/shared/models/user.dart';

// ── Test fixtures ─────────────────────────────────────────────────────────

final _publicUser = User(
  id: 'user-1',
  username: 'ismauo',
  displayName: 'Ismail duo',
  isPrivate: false,
  followersCount: 2,
  followingCount: 1,
  createdAt: DateTime(2024),
);

final _privateUser = _publicUser.copyWith(isPrivate: true);

FollowRequestItem _request(String id) => FollowRequestItem(
      followId: id,
      followerId: 'follower-$id',
      username: 'kma$id',
      displayName: 'Karim $id',
      requestedAt: DateTime(2025),
    );

// ── Fake notifiers ────────────────────────────────────────────────────────

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._user);
  final User _user;
  @override
  Future<User> build() async => _user;
}

class _FakeFollowRequests extends FollowRequestsNotifier {
  _FakeFollowRequests(this._items, {this.onBuild});
  final List<FollowRequestItem> _items;
  final VoidCallback? onBuild;
  @override
  Future<List<FollowRequestItem>> build() async {
    onBuild?.call();
    return _items;
  }
}

// ── Harness ───────────────────────────────────────────────────────────────

/// Pumps the settings sheet already open, over a router that carries the
/// /follow-requests destination so the row's context.push resolves.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required User user,
  required List<FollowRequestItem> requests,
  VoidCallback? onRequestsBuild,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  FlutterSecureStorage.setMockInitialValues({});

  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showProfileSettingsSheet(context, onLogout: () {}),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/follow-requests',
        builder: (_, _) => const Scaffold(body: Text('follow-requests page')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 auto-retries thrown Exceptions; disable so error states
      // surface immediately (matches the app root ProviderScope).
      retry: (_, _) => null,
      overrides: [
        myProfileProvider.overrideWith(() => _FakeMyProfile(user)),
        followRequestsProvider.overrideWith(
          () => _FakeFollowRequests(requests, onBuild: onRequestsBuild),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('settings sheet — Follow requests row', () {
    testWidgets(
        'Given a private account with pending requests, When the sheet opens, '
        'Then the row shows the count', (tester) async {
      await _pumpSheet(
        tester,
        user: _privateUser,
        requests: [_request('a'), _request('b'), _request('c')],
      );

      expect(find.text('Follow Requests'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets(
        'Given a private account with no pending requests, '
        'When the sheet opens, Then the row shows no count',
        (tester) async {
      await _pumpSheet(tester, user: _privateUser, requests: []);

      expect(find.text('Follow Requests'), findsOneWidget);
      // A zero is noise — the detail slot stays empty rather than reading "0".
      expect(find.text('0'), findsNothing);
    });

    testWidgets(
        'Given a public account, When the sheet opens, '
        'Then the row is absent and the requests are never fetched',
        (tester) async {
      var built = false;
      await _pumpSheet(
        tester,
        user: _publicUser,
        requests: [_request('a')],
        onRequestsBuild: () => built = true,
      );

      expect(find.text('Follow Requests'), findsNothing);
      expect(built, isFalse);
      // The neighbouring row is still there — absence is the gate, not a
      // broken section.
      expect(find.text('Blocked accounts'), findsOneWidget);
    });

    testWidgets(
        'Given the row is visible, When it is tapped, '
        'Then the sheet closes and the follow requests screen opens',
        (tester) async {
      await _pumpSheet(
        tester,
        user: _privateUser,
        requests: [_request('a')],
      );

      await tester.tap(find.text('Follow Requests'));
      await tester.pumpAndSettle();

      expect(find.text('follow-requests page'), findsOneWidget);
      expect(find.text('Blocked accounts'), findsNothing);
    });
  });
}
