// test/widgets/search_screen_test.dart
//
// Widget tests for the Editorial SearchScreen redesign.
// Covers:
//   · Top bar — search TextField, help tooltip
//   · Empty query state — placeholder shown
//   · Loading / error states
//   · No-results state (text entered, zero matches)
//   · Results list — section label, display name, @handle, follower count
//   · Private-user lock icon in result row
//   · Clear button — appears after typing, hides + clears on tap

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/search/presentation/search_screen.dart';
import 'package:social_flutter/features/search/providers/search_provider.dart';
import 'package:social_flutter/shared/models/user.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────

User _makeUser({
  String id = 'u-1',
  String username = 'aminad',
  String displayName = 'Amina Diallo',
  bool isPrivate = false,
  int followersCount = 247,
}) =>
    User(
      id: id,
      username: username,
      displayName: displayName,
      avatarUrl: null,
      isPrivate: isPrivate,
      followersCount: followersCount,
      followingCount: 38,
      createdAt: DateTime(2024),
    );

// ── Fake notifiers ────────────────────────────────────────────────────────

class _FakeSearchResults extends SearchResultsNotifier {
  _FakeSearchResults(this._items);
  final List<User> _items;
  @override
  Future<List<User>> build() async => _items;
}

class _FakeSearchResultsLoading extends SearchResultsNotifier {
  @override
  Future<List<User>> build() => Completer<List<User>>().future;
}

class _FakeSearchResultsError extends SearchResultsNotifier {
  @override
  Future<List<User>> build() async => throw Exception('Server error');
}

// ── Widget builder ────────────────────────────────────────────────────────

Widget _buildScreen({
  List<User>? results,
  SearchResultsNotifier Function()? notifier,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      searchResultsProvider.overrideWith(
        notifier ?? () => _FakeSearchResults(results ?? []),
      ),
    ],
    child: const MaterialApp(home: SearchScreen()),
  );
}

// ── Helper: type into the search field ───────────────────────────────────

Future<void> _typeQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(); // setState fires → clears debounce, refreshes UI
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('SearchScreen', () {
    // ── Top bar ──────────────────────────────────────────────────────────

    group('top bar', () {
      testWidgets(
          'Given screen builds, When rendered, '
          'Then search TextField is present', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets(
          'Given screen builds, When rendered, '
          'Then help tooltip is visible', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byTooltip('Search users'), findsOneWidget);
      });
    });

    // ── Empty query state ────────────────────────────────────────────────

    group('empty query state', () {
      testWidgets(
          'Given no text in search field, When screen builds, '
          'Then shows "Search for people to follow" placeholder',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(results: []));
        await tester.pump();

        expect(find.text('Search for people to follow'), findsOneWidget);
      });

      testWidgets(
          'Given no text in search field, When screen builds, '
          'Then clear button is not visible', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byIcon(Icons.close_outlined), findsNothing);
      });
    });

    // ── Loading / error ──────────────────────────────────────────────────

    group('loading and error states', () {
      testWidgets(
          'Given search is loading, When screen builds, '
          'Then shows CircularProgressIndicator', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(notifier: _FakeSearchResultsLoading.new));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets(
          'Given search fails, When screen builds, '
          'Then shows error message', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(notifier: _FakeSearchResultsError.new));
        await tester.pump();

        expect(find.textContaining('Server error'), findsOneWidget);
      });
    });

    // ── No results ───────────────────────────────────────────────────────

    group('no results state', () {
      testWidgets(
          'Given empty results and text entered, When screen renders, '
          'Then shows "No users found." placeholder', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(results: []));
        await tester.pump();
        await _typeQuery(tester, 'nobody');

        expect(find.text('No users found.'), findsOneWidget);
      });
    });

    // ── Results list ─────────────────────────────────────────────────────

    group('results list', () {
      testWidgets(
          'Given results loaded and text entered, When screen renders, '
          'Then shows RESULTS section label with count', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(results: [_makeUser(), _makeUser(id: 'u-2')]));
        await tester.pump();
        await _typeQuery(tester, 'amina');

        expect(find.textContaining('RESULTS'), findsOneWidget);
      });

      testWidgets(
          'Given results loaded and text entered, When screen renders, '
          'Then shows each user display name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(results: [
          _makeUser(id: 'u-1', displayName: 'Amina Diallo'),
          _makeUser(id: 'u-2', displayName: 'Yacine Coulibaly',
              username: 'yac'),
        ]));
        await tester.pump();
        await _typeQuery(tester, 'a');

        expect(find.text('Amina Diallo'), findsOneWidget);
        expect(find.text('Yacine Coulibaly'), findsOneWidget);
      });

      testWidgets(
          'Given result loaded and text entered, When screen renders, '
          'Then shows @handle below display name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(results: [_makeUser(username: 'aminad')]));
        await tester.pump();
        await _typeQuery(tester, 'amina');

        expect(find.text('@aminad'), findsOneWidget);
      });

      testWidgets(
          'Given result with followers and text entered, When rendered, '
          'Then shows follower count', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(results: [_makeUser(followersCount: 247)]));
        await tester.pump();
        await _typeQuery(tester, 'amina');

        expect(find.text('247 followers'), findsOneWidget);
      });

      testWidgets(
          'Given private user in results and text entered, When rendered, '
          'Then shows lock icon', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(results: [_makeUser(isPrivate: true)]));
        await tester.pump();
        await _typeQuery(tester, 'amina');

        expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      });

      testWidgets(
          'Given public user in results and text entered, When rendered, '
          'Then no lock icon shown', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(results: [_makeUser(isPrivate: false)]));
        await tester.pump();
        await _typeQuery(tester, 'amina');

        expect(find.byIcon(Icons.lock_rounded), findsNothing);
      });
    });

    // ── Clear button ─────────────────────────────────────────────────────

    group('clear button', () {
      testWidgets(
          'Given text entered, When typing, '
          'Then clear button appears', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byIcon(Icons.close_outlined), findsNothing);

        await _typeQuery(tester, 'abc');

        expect(find.byIcon(Icons.close_outlined), findsOneWidget);
      });

      testWidgets(
          'Given clear button visible, When tapped, '
          'Then text cleared and placeholder shown', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(results: []));
        await tester.pump();

        await _typeQuery(tester, 'abc');

        expect(find.byIcon(Icons.close_outlined), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_outlined));
        await tester.pump();

        expect(find.byIcon(Icons.close_outlined), findsNothing);
        expect(find.text('Search for people to follow'), findsOneWidget);
      });
    });
  });
}
