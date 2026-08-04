// test/widgets/follow_list_screen_test.dart
//
// Widget tests for the redesigned tabbed FollowListScreen.
// Covers:
//   · Tab selection (initial tab driven by `type` param)
//   · Followers tab — populated list, empty state, error/private state
//   · Pending requests section (own profile only) — visibility and actions
//   · Following tab — populated list, empty state
//
// All HTTP + secure-storage calls are prevented by faking the Riverpod
// notifiers that the screen depends on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'; // Riverpod 3 exports the Override type here
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/follows/presentation/follow_list_screen.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/shared/models/user.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────

const _ownUserId = 'me-1';
const _otherUserId = 'other-1';

final _ownUser = User(
  id: _ownUserId,
  username: 'ismauo',
  displayName: 'Ismail duo',
  avatarUrl: null,
  isPrivate: true,
  followersCount: 2,
  followingCount: 1,
  createdAt: DateTime(2024),
);

const _follower1 = FollowerListItem(
  id: 'f-1',
  username: 'yac',
  displayName: 'Yacine Coulibaly',
  isPrivate: false,
);

const _follower2 = FollowerListItem(
  id: 'f-2',
  username: 'linab',
  displayName: 'Lina Bensaïd',
  isPrivate: false,
);

const _following1 = FollowerListItem(
  id: 'other-1',
  username: 'aminad',
  displayName: 'Amina Diallo',
  isPrivate: false,
);

final _pendingRequest = FollowRequestItem(
  followId: 'req-1',
  followerId: 'req-user-1',
  username: 'kma',
  displayName: 'Karim Maalouf',
  requestedAt: DateTime(2025),
);

// ── Fake notifiers ────────────────────────────────────────────────────────

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._user);
  final User _user;
  @override
  Future<User> build() async => _user;
}

class _FakeFollowers extends FollowersNotifier {
  _FakeFollowers(this._items) : super(''); // family arg unused by the fake
  final List<FollowerListItem> _items;
  @override
  Future<List<FollowerListItem>> build() async => _items;
}

class _FakeFollowersError extends FollowersNotifier {
  _FakeFollowersError() : super('');
  @override
  Future<List<FollowerListItem>> build() async =>
      throw Exception('403 Forbidden');
}

class _FakeFollowing extends FollowingNotifier {
  _FakeFollowing(this._items) : super(''); // family arg unused by the fake
  final List<FollowerListItem> _items;
  @override
  Future<List<FollowerListItem>> build() async => _items;
}

class _FakeFollowRequests extends FollowRequestsNotifier {
  _FakeFollowRequests(this._items);
  final List<FollowRequestItem> _items;
  @override
  Future<List<FollowRequestItem>> build() async => _items;
  @override
  Future<void> acceptRequest(String followId) async {
    state.whenData((r) =>
        state = AsyncData(r.where((x) => x.followId != followId).toList()));
  }
  @override
  Future<void> rejectRequest(String followId) async {
    state.whenData((r) =>
        state = AsyncData(r.where((x) => x.followId != followId).toList()));
  }
}

// ── Widget builder ────────────────────────────────────────────────────────

Widget _buildScreen({
  required String userId,
  FollowListType type = FollowListType.followers,
  User? myProfile,
  List<FollowerListItem>? followers,
  List<FollowerListItem>? following,
  List<FollowRequestItem>? requests,
  bool followersError = false,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    // Riverpod 3 auto-retries thrown Exceptions; disable so error-state
    // tests surface AsyncError immediately (matches app root ProviderScope).
    retry: (_, _) => null,
    overrides: [
      myProfileProvider.overrideWith(
          () => _FakeMyProfile(myProfile ?? _ownUser)),
      followersProvider.overrideWith2(followersError
          ? (_) => _FakeFollowersError()
          : (_) => _FakeFollowers(followers ?? [])),
      followingProvider
          .overrideWith2((_) => _FakeFollowing(following ?? [])),
      followRequestsProvider.overrideWith(
          () => _FakeFollowRequests(requests ?? [])),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FollowListScreen(userId: userId, type: type),
    ),
  );
}

List<Override> _providerOverrides({
  User? myProfile,
  List<FollowerListItem>? followers,
  List<FollowerListItem>? following,
  List<FollowRequestItem>? requests,
  bool followersError = false,
}) =>
    [
      myProfileProvider.overrideWith(() => _FakeMyProfile(myProfile ?? _ownUser)),
      followersProvider.overrideWith2(followersError
          ? (_) => _FakeFollowersError()
          : (_) => _FakeFollowers(followers ?? [])),
      followingProvider.overrideWith2((_) => _FakeFollowing(following ?? [])),
      followRequestsProvider
          .overrideWith(() => _FakeFollowRequests(requests ?? [])),
    ];

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('FollowListScreen', () {
    // ── Tab selection ────────────────────────────────────────────────────

    group('tab selection', () {
      testWidgets(
          'Given type followers, When screen builds, '
          'Then Followers tab is visible', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
        ));
        await tester.pump();

        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
      });

      testWidgets(
          'Given type following, When screen builds, '
          'Then Following tab is visible', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.following,
        ));
        await tester.pump();

        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
      });

      testWidgets(
          'Given type followers, When Following tab tapped, '
          'Then following section becomes visible', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          following: [_following1],
        ));
        await tester.pump();

        await tester.pump(); // settle provider data

        await tester.tap(find.textContaining('Following').last);
        await tester.pumpAndSettle();

        expect(find.text('Amina Diallo'), findsOneWidget);
      });
    });

    // ── Followers tab ────────────────────────────────────────────────────

    group('followers tab', () {
      testWidgets(
          'Given followers loaded, When on followers tab, '
          'Then shows each follower display name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          followers: [_follower1, _follower2],
        ));
        await tester.pump();

        expect(find.text('Yacine Coulibaly'), findsOneWidget);
        expect(find.text('Lina Bensaïd'), findsOneWidget);
      });

      testWidgets(
          'Given followers loaded, When follower row found, '
          'Then the row is present and shows the @handle', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          followers: [_follower1],
        ));
        await tester.pump();
        await tester.pump();

        expect(find.text('Yacine Coulibaly'), findsOneWidget);
        expect(find.text('@yac'), findsOneWidget);
      });

      testWidgets(
          'Given no followers, When on followers tab, '
          'Then shows "No followers yet." placeholder', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          followers: [],
        ));
        await tester.pump();

        expect(find.text('No followers yet.'), findsOneWidget);
      });

      testWidgets(
          'Given fetch error, When on followers tab, '
          'Then shows lock placeholder', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _otherUserId,
          type: FollowListType.followers,
          followersError: true,
        ));
        await tester.pump();

        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      });
    });

    // ── Pending requests ─────────────────────────────────────────────────

    group('pending requests section (own profile)', () {
      testWidgets(
          'Given own profile with pending requests, '
          'When on followers tab, Then shows FOLLOW REQUESTS section',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          requests: [_pendingRequest],
        ));
        await tester.pump();
        await tester.pump();

        expect(
            find.textContaining('FOLLOW REQUESTS'), findsOneWidget);
        expect(find.text('Karim Maalouf'), findsOneWidget);
        expect(find.text('Confirm'), findsOneWidget);
      });

      testWidgets(
          'Given own profile without pending requests, '
          'When on followers tab, Then no requests section', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          requests: [],
        ));
        await tester.pump();

        expect(
            find.textContaining('FOLLOW REQUESTS'), findsNothing);
      });

      testWidgets(
          'Given other profile viewed, '
          'When on followers tab, Then pending requests never shown',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // userId differs from myProfile.id → not own profile
        await tester.pumpWidget(_buildScreen(
          userId: _otherUserId,
          type: FollowListType.followers,
          requests: [_pendingRequest], // would show if own profile
        ));
        await tester.pump();

        expect(
            find.textContaining('FOLLOW REQUESTS'), findsNothing);
      });

      testWidgets(
          'Given pending request visible, When Confirm tapped, '
          'Then request row disappears', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          requests: [_pendingRequest],
        ));
        await tester.pump();
        await tester.pump(); // settle followRequestsProvider

        expect(find.text('Karim Maalouf'), findsOneWidget);

        await tester.tap(
            find.byKey(const Key('confirmRequest_req-1')));
        await tester.pump();

        expect(find.text('Karim Maalouf'), findsNothing);
      });

      testWidgets(
          'Given pending request visible, When Decline tapped, '
          'Then request row disappears', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          requests: [_pendingRequest],
        ));
        await tester.pump();
        await tester.pump();

        await tester.tap(
            find.byKey(const Key('declineRequest_req-1')));
        await tester.pumpAndSettle(); // ConfirmDialog entrance is 220ms
        await tester.tap(find.text('Decline')); // declineRequestConfirm
        await tester.pumpAndSettle();

        expect(find.text('Karim Maalouf'), findsNothing);
      });

      testWidgets(
          'Given decline confirmation shown, When cancelled, '
          'Then request row remains', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.followers,
          requests: [_pendingRequest],
        ));
        await tester.pump();
        await tester.pump();

        await tester.tap(
            find.byKey(const Key('declineRequest_req-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Karim Maalouf'), findsOneWidget);
      });
    });

    // ── Following tab ────────────────────────────────────────────────────

    group('following tab', () {
      testWidgets(
          'Given following loaded, When on following tab, '
          'Then shows each followed user name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.following,
          following: [_following1],
        ));
        await tester.pump();

        expect(find.text('Amina Diallo'), findsOneWidget);
      });

      testWidgets(
          'Given no following, When on following tab, '
          'Then shows "Not following anyone yet." placeholder',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.following,
          following: [],
        ));
        await tester.pump();

        // Navigate to the following tab
        await tester.tap(find.text('Following'));
        await tester.pumpAndSettle();

        expect(
            find.text('Not following anyone yet.'), findsOneWidget);
      });
    });

    // ── Navigation — profileBaseRoute ─────────────────────────────────────

    group('navigation — profileBaseRoute', () {
      Widget buildRouterScreen({
        required GoRouter router,
        List<FollowerListItem>? followers,
        List<FollowerListItem>? following,
      }) {
        FlutterSecureStorage.setMockInitialValues({});
        return ProviderScope(
          // Riverpod 3 auto-retries thrown Exceptions; disable so error-state
          // tests surface AsyncError immediately (matches app root ProviderScope).
          retry: (_, _) => null,
          overrides: _providerOverrides(
              followers: followers, following: following),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        );
      }

      testWidgets(
          'Given profileBaseRoute=/search/profile, '
          'When follower row tapped, '
          'Then navigates to /search/profile/{userId}', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          initialLocation: '/list',
          routes: [
            GoRoute(
              path: '/list',
              builder: (_, __) => FollowListScreen(
                userId: _otherUserId,
                type: FollowListType.followers,
                profileBaseRoute: '/search/profile',
              ),
            ),
            GoRoute(
              path: '/search/profile/:userId',
              builder: (_, s) => Scaffold(
                body: Text('profile:${s.pathParameters['userId']}'),
              ),
            ),
          ],
        );

        await tester.pumpWidget(buildRouterScreen(
          router: router,
          followers: [_follower1],
        ));
        await tester.pump();

        await tester.tap(find.text('Yacine Coulibaly'));
        await tester.pumpAndSettle();

        expect(find.text('profile:f-1'), findsOneWidget);
      });

      testWidgets(
          'Given default profileBaseRoute, '
          'When follower row tapped, '
          'Then navigates to /profile/{userId}', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          initialLocation: '/list',
          routes: [
            GoRoute(
              path: '/list',
              builder: (_, __) => FollowListScreen(
                userId: _otherUserId,
                type: FollowListType.followers,
              ),
            ),
            GoRoute(
              path: '/profile/:userId',
              builder: (_, s) => Scaffold(
                body: Text('profile:${s.pathParameters['userId']}'),
              ),
            ),
          ],
        );

        await tester.pumpWidget(buildRouterScreen(
          router: router,
          followers: [_follower1],
        ));
        await tester.pump();

        await tester.tap(find.text('Yacine Coulibaly'));
        await tester.pumpAndSettle();

        expect(find.text('profile:f-1'), findsOneWidget);
      });
    });

    // ── Top bar ──────────────────────────────────────────────────────────

    group('top bar', () {
      testWidgets(
          'Given own profile, When screen builds, '
          'Then shows @handle in top bar', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(userId: _ownUserId));
        await tester.pump();

        expect(find.text('@ismauo'), findsOneWidget);
      });
    });
  });
}
