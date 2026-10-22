// test/widgets/follow_actions_test.dart
//
// The async gap in confirmAndRemoveFollower: it awaits a confirm dialog and
// then a network DELETE. If the user leaves the screen while the DELETE is in
// flight, the server has still removed the follower — so the keep-alive list
// must still drop the row, and nothing may touch the departed screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/confirm_dialog.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/presentation/follow_actions.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/follow_counts.dart';

const _meId = 'me-1';

final _me = User(
  id: _meId,
  username: 'ismauo',
  isPrivate: true,
  followersCount: 2,
  followingCount: 0,
  createdAt: DateTime(2024),
);

const _yac = FollowerListItem(
  id: 'f-1',
  username: 'yac',
  displayName: 'Yacine Coulibaly',
  isPrivate: false,
);

const _lina = FollowerListItem(
  id: 'f-2',
  username: 'linab',
  displayName: 'Lina Bensaïd',
  isPrivate: false,
);

class _FakeMyProfile extends MyProfileNotifier {
  @override
  Future<User> build() async => _me;
}

class _FakeFollowers extends FollowersNotifier {
  _FakeFollowers() : super(_meId);
  @override
  Future<List<FollowerListItem>> build() async => const [_yac, _lina];
}

/// removeFollower completes only when the test says so, so the screen can be
/// left while the request is in flight.
class _SlowFollowRepo implements FollowRepository {
  final Completer<FollowCounts> gate = Completer<FollowCounts>();
  bool called = false;

  @override
  Future<FollowCounts> removeFollower(String userId) {
    called = true;
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Home shows the keep-alive followers list; a pushed route carries the
/// action, so popping it disposes the caller while the list lives on.
Widget _host({
  required FollowRepository repo,
  required GlobalKey<NavigatorState> navKey,
}) {
  return ProviderScope(
    overrides: [
      myProfileProvider.overrideWith(_FakeMyProfile.new),
      followersProvider.overrideWith2((_) => _FakeFollowers()),
      followRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      navigatorKey: navKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) {
          final rows = ref.watch(followersProvider(_meId)).value ?? const [];
          return Scaffold(
            body: Column(
              children: [
                for (final row in rows) Text(row.displayName!),
                ElevatedButton(
                  onPressed: () => navKey.currentState!.push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Consumer(
                          builder: (context, ref, _) => ElevatedButton(
                            onPressed: () => confirmAndRemoveFollower(
                              context,
                              ref,
                              userId: _yac.id,
                              username: _yac.username,
                            ),
                            child: const Text('go'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets(
      'Given a removal in flight, When the screen is left before it lands, '
      'Then the cached list still drops the row and nothing throws',
      (tester) async {
    final repo = _SlowFollowRepo();
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(_host(repo: repo, navKey: navKey));
    await tester.pumpAndSettle();
    expect(find.text('Yacine Coulibaly'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(ConfirmDialog), matching: find.text('Remove')));
    await tester.pump();
    expect(repo.called, isTrue);

    // The user leaves while the DELETE is still in flight.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();

    // Now it lands, against an unmounted caller.
    repo.gate.complete(kZeroCounts);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Yacine Coulibaly'), findsNothing,
        reason: 'the server removed them; the cache must agree');
    expect(find.text('Lina Bensaïd'), findsOneWidget);
    // Told nothing — the screen it would have spoken for is gone.
    expect(find.text('Removed @yac from your followers.'), findsNothing);
  });
}
