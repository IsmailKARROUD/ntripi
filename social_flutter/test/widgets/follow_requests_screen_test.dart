// test/widgets/follow_requests_screen_test.dart
//
// Two defects of the same shape, both about a user trying to ask again:
//
//   The RefreshIndicator used to live inside the data branch, *after* the
//   isEmpty early return — so "no requests" and a failed load, the two states
//   where the user most wants to re-check, were the two with no way to.
//
//   followRequestsProvider is keep-alive, so the second visit rendered whatever
//   the first one fetched. A request that arrived in between stayed invisible.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';
import 'package:social_flutter/features/follows/presentation/follow_requests_screen.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/follow.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeFollowRepo extends FollowRepository {
  _FakeFollowRepo({this.rows = const []}) : super(Dio());

  /// Swapped mid-test to stand in for a request arriving server-side.
  List<FollowRequestItem> rows;
  bool fail = false;
  int calls = 0;

  @override
  Future<List<FollowRequestItem>> getFollowRequests({
    bool forceRefresh = false,
  }) async {
    calls++;
    if (fail) throw DioException(requestOptions: RequestOptions());
    return rows;
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────

FollowRequestItem _request(String username) => FollowRequestItem(
      followId: 'follow-$username',
      followerId: 'user-$username',
      username: username,
      displayName: 'Display $username',
      avatarUrl: null,
      requestedAt: DateTime.utc(2026, 8, 3),
    );

ProviderContainer _container(_FakeFollowRepo repo) => ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        followRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );

/// The container is passed in rather than created per-pump, because the bug
/// under test only exists while provider state OUTLIVES the screen — a fresh
/// ProviderScope would rebuild followRequestsProvider and fetch cleanly, hiding
/// exactly the staleness these tests exist to catch.
Widget _screen(ProviderContainer container, {bool showScreen = true}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: showScreen ? const FollowRequestsScreen() : const SizedBox.shrink(),
      ),
    );

/// Leave the screen and come back, with the provider container left standing.
Future<void> _reopen(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(_screen(container, showScreen: false));
  await tester.pump();
  await tester.pumpWidget(_screen(container));
  await tester.pumpAndSettle();
}

/// Drag far enough to trip the RefreshIndicator, then let it settle.
Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.fling(
    find.byType(RefreshIndicator),
    const Offset(0, 320),
    1000,
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
      'Given there are no pending requests, '
      'When the empty state is pulled down, '
      'Then it refreshes', (tester) async {
    final repo = _FakeFollowRepo();
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.noRequests), findsOneWidget);

    final before = repo.calls;
    await _pullToRefresh(tester);

    // Nothing to scroll here, which is why the physics have to be forced —
    // without that the drag never reaches the indicator at all.
    expect(repo.calls, greaterThan(before));
  });

  testWidgets(
      'Given the list failed to load, '
      'When the error state is pulled down, '
      'Then it refreshes', (tester) async {
    final repo = _FakeFollowRepo()..fail = true;
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    final before = repo.calls;
    repo.fail = false;
    repo.rows = [_request('ada')];
    await _pullToRefresh(tester);

    expect(repo.calls, greaterThan(before));
    expect(find.textContaining('Display ada'), findsOneWidget);
  });

  testWidgets(
      'Given a request arrived since the list was last loaded, '
      'When the screen is reopened, '
      'Then it is refetched rather than served from the keep-alive provider',
      (tester) async {
    final repo = _FakeFollowRepo(rows: [_request('ada')]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    repo.rows = [_request('ada'), _request('grace')];
    await _reopen(tester, container);

    expect(find.textContaining('Display grace'), findsOneWidget);
  });

  testWidgets(
      'Given a loaded list, '
      'When the on-open refetch fails, '
      'Then the rows stay put and no error page replaces them', (tester) async {
    final repo = _FakeFollowRepo(rows: [_request('ada')]);
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    repo.fail = true;
    await _reopen(tester, container);

    // Nobody asked for that read, so its failure is not news worth showing.
    expect(find.textContaining('Display ada'), findsOneWidget);
  });
}
