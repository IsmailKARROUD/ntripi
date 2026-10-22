// test/widgets/follow_counts_answer_test.dart — a follow write's answer is the
// counts, and nothing downloads a profile after it.
//
// Follow and accept answer with both accounts' counts; unfollow, remove
// follower and block do when asked. The app adopts them — mine on my profile,
// theirs on their profile where it is loaded — and never reads /users/me or
// their profile again for them, nor adds or subtracts one itself, which would
// count twice from a stale row. Real repositories on one mocked Dio, so "no
// GET" is an exact assertion.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/ui/confirm_dialog.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/presentation/follow_actions.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/presentation/profile_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/reports/data/report_repository.dart';
import 'package:ntripi/features/reports/presentation/ugc_actions.dart';
import 'package:ntripi/l10n/app_localizations.dart';

import '../support/recording_dio.dart';

const _me = 'me-1';
const _them = 'them-1';

Map<String, dynamic> _userJson(
  String id, {
  required int followers,
  required int following,
  bool isFollowing = false,
  bool followsYou = false,
}) =>
    {
      'id': id,
      'username': 'user$id',
      'display_name': null,
      'avatar_url': null,
      // A cover, so the profile draws no map and asks for no locations.
      'cover_image_url': 'https://images.example/cover.jpg',
      'is_private': false,
      'followers_count': followers,
      'following_count': following,
      'is_following': isFollowing,
      'follow_is_pending': false,
      'follows_you': followsYou,
      'created_at': '2026-01-01T00:00:00Z',
    };

/// Both accounts' counts, as a follow write answers them.
Map<String, dynamic> _counts(
  ({int followers, int following}) me, [
  ({int followers, int following})? them,
]) =>
    {
      'me': {'followers_count': me.followers, 'following_count': me.following},
      'them': them == null
          ? null
          : {
              'followers_count': them.followers,
              'following_count': them.following,
            },
    };

Map<String, dynamic> _followJson({String status = 'accepted'}) => {
      'id': 'follow-1',
      'follower_id': _me,
      'following_id': _them,
      'status': status,
      'created_at': '2026-10-22T09:00:00Z',
    };

/// The app's repositories on one recording Dio, with my profile and theirs as
/// the server has them before the write.
class _Server {
  _Server({
    ({int followers, int following}) me = (followers: 1, following: 0),
    bool iFollowThem = false,
    bool theyFollowMe = false,
  }) {
    api.adapter
      ..onGet(kMyProfileEndpoint, (server) => server.reply(200,
          _userJson(_me, followers: me.followers, following: me.following)))
      ..onGet(userProfileEndpoint(_them), (server) => server.reply(200,
          _userJson(_them,
              followers: 247,
              following: 38,
              isFollowing: iFollowThem,
              followsYou: theyFollowMe)))
      ..onGet(userItinerariesEndpoint(_them), (server) => server.reply(200, []))
      ..onGet(kMyBlocksEndpoint, (server) => server.reply(200, []));
  }

  final api = RecordingDio();

  late final container = ProviderContainer(overrides: [
    profileRepositoryProvider.overrideWithValue(ProfileRepository(api.dio)),
    followRepositoryProvider.overrideWithValue(FollowRepository(api.dio)),
    reportRepositoryProvider.overrideWithValue(ReportRepository(api.dio)),
    itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(api.dio)),
  ]);

  int get myFollowers => container.read(myProfileProvider).value!.followersCount;
  int get myFollowing => container.read(myProfileProvider).value!.followingCount;
  int get theirFollowers =>
      container.read(userProfileProvider(_them)).value!.followersCount;
}

Widget _app(_Server server, Widget home) => UncontrolledProviderScope(
      container: server.container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

/// A button that runs [action] — the flows under test need a BuildContext for
/// their confirmation dialogs.
Widget _actionButton(
  Future<void> Function(BuildContext context, WidgetRef ref) action,
) =>
    Scaffold(
      body: Consumer(
        builder: (context, ref, _) => ElevatedButton(
          onPressed: () => action(context, ref),
          child: const Text('go'),
        ),
      ),
    );

/// Both profiles as the app had them before the write, then a clean log.
Future<void> _loadProfiles(WidgetTester tester, _Server server) async {
  server.container.read(myProfileProvider);
  server.container.read(userProfileProvider(_them));
  await tester.pumpAndSettle();
  server.api.sent.clear();
}

Future<void> _confirm(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
      of: find.byType(ConfirmDialog), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // The cover is a network image the test cannot load.
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == 'image resource service') return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  });

  testWidgets(
      'Given their profile, When I follow and then unfollow, '
      'Then both tallies come from the answers and no profile is read again',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final server = _Server();
    addTearDown(server.container.dispose);
    await tester.pumpWidget(_app(server, const ProfileScreen(userId: _them)));
    await _loadProfiles(tester, server);

    server.api.adapter.onPost(followEndpoint(_them), (r) => r.reply(201, {
          ..._followJson(),
          'counts': _counts((followers: 1, following: 1),
              (followers: 248, following: 38)),
        }));
    await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
    await tester.pumpAndSettle();

    expect(server.api.lines, ['POST ${followEndpoint(_them)}']);
    expect(find.text('248'), findsOneWidget);
    expect((server.theirFollowers, server.myFollowing), (248, 1));

    server.api.sent.clear();
    server.api.adapter.onDelete(
      followEndpoint(_them),
      (r) => r.reply(200,
          _counts((followers: 1, following: 0), (followers: 247, following: 38))),
      queryParameters: {'return': 'counts'},
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Following'));
    await _confirm(tester, 'Unfollow');

    expect(server.api.lines, ['DELETE ${followEndpoint(_them)}']);
    expect(find.text('247'), findsOneWidget);
    expect((server.theirFollowers, server.myFollowing), (247, 0));
  });

  testWidgets(
      'Given they follow me, When I remove them, '
      'Then both counts come from the answer and no profile is read again',
      (tester) async {
    final server = _Server(me: (followers: 5, following: 0), theyFollowMe: true);
    addTearDown(server.container.dispose);
    await tester.pumpWidget(_app(server, _actionButton(
        (context, ref) => confirmAndRemoveFollower(context, ref,
            userId: _them, username: 'userthem-1'))));
    await _loadProfiles(tester, server);
    server.api.adapter.onDelete(
      removeFollowerEndpoint(_them),
      (r) => r.reply(200,
          _counts((followers: 4, following: 0), (followers: 247, following: 37))),
      queryParameters: {'return': 'counts'},
    );

    await tester.tap(find.text('go'));
    await _confirm(tester, 'Remove');

    expect(server.api.lines, ['DELETE ${removeFollowerEndpoint(_them)}']);
    expect(server.myFollowers, 4);
    final them = server.container.read(userProfileProvider(_them)).value!;
    expect((them.followingCount, them.followsYou), (37, false));
  });

  testWidgets(
      'Given I follow them, When I unfollow from my Following list, '
      'Then both counts come from the answer and no profile is read again',
      (tester) async {
    final server = _Server(me: (followers: 0, following: 3), iFollowThem: true);
    addTearDown(server.container.dispose);
    await tester.pumpWidget(_app(server, _actionButton(
        (context, ref) => confirmAndUnfollow(context, ref,
            userId: _them, username: 'userthem-1'))));
    await _loadProfiles(tester, server);
    server.api.adapter.onDelete(
      followEndpoint(_them),
      (r) => r.reply(200,
          _counts((followers: 0, following: 2), (followers: 246, following: 38))),
      queryParameters: {'return': 'counts'},
    );

    await tester.tap(find.text('go'));
    await _confirm(tester, 'Unfollow');

    expect(server.api.lines, ['DELETE ${followEndpoint(_them)}']);
    expect(server.myFollowing, 2);
    final them = server.container.read(userProfileProvider(_them)).value!;
    expect((them.followersCount, them.isFollowing), (246, false));
  });

  testWidgets(
      'Given I follow them, When I block them, '
      'Then my counts come from the answer and /users/me is not read again',
      (tester) async {
    final server = _Server(me: (followers: 0, following: 1), iFollowThem: true);
    addTearDown(server.container.dispose);
    await tester.pumpWidget(_app(server, _actionButton(
        (context, ref) => confirmAndBlock(context, ref,
            userId: _them, username: 'userthem-1'))));
    await _loadProfiles(tester, server);
    server.api.adapter.onPost(
      kBlockEndpoint(_them),
      (r) => r.reply(200, _counts((followers: 0, following: 0))),
      queryParameters: {'return': 'counts'},
    );

    await tester.tap(find.text('go'));
    await _confirm(tester, 'Block');

    expect(server.api.lines, ['POST ${kBlockEndpoint(_them)}']);
    expect(server.myFollowing, 0);
  });

  test('accepting a request adopts my new followers count — nothing refreshed '
      'it before', () async {
    final server = _Server(me: (followers: 2, following: 0));
    addTearDown(server.container.dispose);
    server.api.adapter
      ..onGet(kFollowRequestsEndpoint, (r) => r.reply(200, [
            {
              'follow_id': 'follow-1',
              'follower_id': _them,
              'username': 'userthem-1',
              'display_name': null,
              'avatar_url': null,
              'requested_at': '2026-10-22T08:00:00Z',
            },
          ]))
      ..onPost(acceptFollowRequestEndpoint('follow-1'), (r) => r.reply(200, {
            ..._followJson(),
            'counts': _counts((followers: 3, following: 0),
                (followers: 247, following: 39)),
          }));
    await server.container.read(myProfileProvider.future);
    await server.container.read(followRequestsProvider.future);
    server.api.sent.clear();

    await server.container
        .read(followRequestsProvider.notifier)
        .acceptRequest('follow-1');

    expect(server.api.lines, ['POST ${acceptFollowRequestEndpoint('follow-1')}']);
    expect(server.myFollowers, 3);
    expect(server.container.read(followRequestsProvider).value, isEmpty);
  });
}
