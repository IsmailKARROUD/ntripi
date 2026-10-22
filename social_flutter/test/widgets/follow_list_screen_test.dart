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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'; // Riverpod 3 exports the Override type here
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/ui/confirm_dialog.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/presentation/follow_list_screen.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/follow_counts.dart';

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

/// Records the two row-action mutations; [failWith] makes both throw it.
class _RecordingFollowRepo implements FollowRepository {
  _RecordingFollowRepo({this.failWith});
  final Object? failWith;
  final List<String> removed = [];
  final List<String> unfollowed = [];

  @override
  Future<FollowCounts> removeFollower(String userId) async {
    if (failWith != null) throw failWith!;
    removed.add(userId);
    return kZeroCounts;
  }

  @override
  Future<FollowCounts> unfollowUser(String userId) async {
    if (failWith != null) throw failWith!;
    unfollowed.add(userId);
    return kZeroCounts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The shape the repository throws for a coded API error.
DioException _apiError(int status, String code) {
  final request = RequestOptions(path: '/users');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: status,
      data: {'code': code, 'detail': 'Server said no.'},
    ),
  );
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
  FollowRepository? repo,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    // Riverpod 3 auto-retries thrown Exceptions; disable so error-state
    // tests surface AsyncError immediately (matches app root ProviderScope).
    retry: (_, _) => null,
    overrides: [
      if (repo != null) followRepositoryProvider.overrideWithValue(repo),
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

        // Labels carry the profile's totals (fixture: 2 / 1), not the length
        // of the loaded page — a page undercounts anyone past the first one.
        expect(find.text('2 Followers'), findsOneWidget);
        expect(find.text('1 Following'), findsOneWidget);
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

        // Labels carry the profile's totals (fixture: 2 / 1), not the length
        // of the loaded page — a page undercounts anyone past the first one.
        expect(find.text('2 Followers'), findsOneWidget);
        expect(find.text('1 Following'), findsOneWidget);
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

        // Navigate to the following tab (label carries the fixture's total)
        await tester.tap(find.text('1 Following'));
        await tester.pumpAndSettle();

        expect(
            find.text('Not following anyone yet.'), findsOneWidget);
      });
    });

    // ── Removing a follower (own Followers list) ─────────────────────────

    group('remove follower (own list)', () {
      testWidgets(
          'Given own followers list, When screen builds, '
          'Then each follower row offers Remove', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          followers: [_follower1, _follower2],
        ));
        await tester.pump();

        expect(find.byKey(const Key('removeFollower_f-1')), findsOneWidget);
        expect(find.byKey(const Key('removeFollower_f-2')), findsOneWidget);
        expect(find.text('Remove'), findsNWidgets(2));
      });

      testWidgets(
          "Given someone else's followers list, When screen builds, "
          'Then no row offers Remove', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _otherUserId,
          followers: [_follower1],
        ));
        await tester.pump();

        expect(find.text('Remove'), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets(
          'Given the Remove pill, When a screen reader reads it, '
          'Then it hears whom the button removes', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          followers: [_follower1],
        ));
        await tester.pump();

        // A bare "Remove" in a list says nothing about whom.
        expect(
          tester.getSemantics(find.byKey(const Key('removeFollower_f-1'))),
          isSemantics(
            label: 'Remove @yac from your followers',
            isButton: true,
            hasTapAction: true,
          ),
        );
        semantics.dispose();
      });

      testWidgets(
          'Given a follower, When Remove is confirmed, Then the server is '
          'asked, the row goes and a snackbar says so', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _RecordingFollowRepo();
        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          followers: [_follower1, _follower2],
          repo: repo,
        ));
        await tester.pump();

        await tester.tap(find.byKey(const Key('removeFollower_f-1')));
        await tester.pumpAndSettle(); // ConfirmDialog entrance is 220ms
        // The fixture account is private: getting back in takes a request.
        expect(find.text('Remove @yac from your followers?'), findsOneWidget);
        expect(find.textContaining('send a new request'), findsOneWidget);
        await tester.tap(find.descendant(
            of: find.byType(ConfirmDialog), matching: find.text('Remove')));
        await tester.pumpAndSettle();

        expect(repo.removed, ['f-1']);
        expect(find.text('Yacine Coulibaly'), findsNothing);
        expect(find.text('Lina Bensaïd'), findsOneWidget);
        expect(find.text('Removed @yac from your followers.'), findsOneWidget);
      });

      testWidgets(
          'Given a public account, When Remove is tapped, '
          'Then the dialog warns they can follow straight back',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          myProfile: _ownUser.copyWith(isPrivate: false),
          followers: [_follower1],
          repo: _RecordingFollowRepo(),
        ));
        await tester.pump();

        await tester.tap(find.byKey(const Key('removeFollower_f-1')));
        await tester.pumpAndSettle();

        expect(find.textContaining('can follow you again'), findsOneWidget);
        expect(find.textContaining('send a new request'), findsNothing);
      });

      testWidgets(
          'Given the Remove dialog, When cancelled, '
          'Then nothing is sent and the row stays', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _RecordingFollowRepo();
        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          followers: [_follower1],
          repo: repo,
        ));
        await tester.pump();

        await tester.tap(find.byKey(const Key('removeFollower_f-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(repo.removed, isEmpty);
        expect(find.text('Yacine Coulibaly'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
      });

      testWidgets(
          'Given the server refuses, When Remove is confirmed, '
          'Then the row stays and its pill comes back', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          followers: [_follower1],
          repo: _RecordingFollowRepo(
              failWith: _apiError(500, 'internal_error')),
        ));
        await tester.pump();

        await tester.tap(find.byKey(const Key('removeFollower_f-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(
            of: find.byType(ConfirmDialog), matching: find.text('Remove')));
        await tester.pumpAndSettle();

        expect(find.text('Yacine Coulibaly'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    });

    // ── Unfollowing from the own Following list ──────────────────────────

    group('unfollow (own following list)', () {
      testWidgets(
          'Given own following list, When screen builds, '
          'Then each row offers a Following pill', (tester) async {
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

        expect(find.byKey(const Key('unfollow_other-1')), findsOneWidget);
        // The tab label reads "1 Following"; only the pill is exactly this.
        expect(find.text('Following'), findsOneWidget);
      });

      testWidgets(
          "Given someone else's following list, When screen builds, "
          'Then no row offers to unfollow', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _otherUserId,
          type: FollowListType.following,
          following: [_follower1],
        ));
        await tester.pump();

        expect(find.byKey(const Key('unfollow_f-1')), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets(
          'Given a followed account, When Following is confirmed, '
          'Then it unfollows, the row goes and a snackbar says so',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _RecordingFollowRepo();
        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.following,
          following: [_following1],
          repo: repo,
        ));
        await tester.pump();

        await tester.tap(find.byKey(const Key('unfollow_other-1')));
        await tester.pumpAndSettle();
        // The same dialog the profile's Following button shows.
        expect(find.text('Unfollow @aminad?'), findsOneWidget);
        await tester.tap(find.text('Unfollow'));
        await tester.pumpAndSettle();

        expect(repo.unfollowed, ['other-1']);
        expect(find.text('Amina Diallo'), findsNothing);
        expect(find.text('Unfollowed @aminad'), findsOneWidget);
      });

      testWidgets(
          'Given the follow already ended elsewhere, When Following is '
          'confirmed, Then the stale row goes without an error',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          userId: _ownUserId,
          type: FollowListType.following,
          following: [_following1],
          repo: _RecordingFollowRepo(
              failWith: _apiError(404, 'not_following')),
        ));
        await tester.pump();

        await tester.tap(find.byKey(const Key('unfollow_other-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unfollow'));
        await tester.pumpAndSettle();

        expect(find.text('Amina Diallo'), findsNothing);
        expect(find.text('Unfollowed @aminad'), findsOneWidget);
        expect(find.text('You are not following this user.'), findsNothing);
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
