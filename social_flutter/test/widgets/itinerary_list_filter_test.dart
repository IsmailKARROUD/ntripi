// test/widgets/itinerary_list_filter_test.dart — the Itineraries tab now holds
// two groups that arrive from two endpoints: trips the viewer owns, and trips
// somebody else owns and granted them edit rights on.
//
// Two properties are load-bearing. A shared row must never offer the owner-only
// delete gesture — that is decided by the row's PROVENANCE, so a bug in the
// merge shows up here rather than as a 403 after the user typed a trip title
// into a confirm dialog. And the Mine segment must survive a dead
// shared-with-me call, because the two lists fail independently.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/feed/domain/feed_item.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_list_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/shared_itinerary_card.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

Itinerary _itinerary({
  required String id,
  required String title,
  required String ownerId,
  required DateTime createdAt,
  int stops = 0,
}) {
  return Itinerary(
    id: id,
    userId: ownerId,
    title: title,
    totalDurationMin: 60 * stops,
    totalCost: 0.0,
    currency: 'EUR',
    visibility: ItineraryVisibility.restricted,
    createdAt: createdAt,
    updatedAt: createdAt,
    stopsCount: stops,
  );
}

// Mine: one trip, created in the middle of the shared pair, so a merge that
// simply concatenates the two lists fails the ordering assertion.
final _mine = [
  _itinerary(
    id: 'mine-1',
    title: 'My Lisbon trip',
    ownerId: 'me',
    createdAt: DateTime.utc(2026, 8, 10),
    stops: 3,
  ),
];

final _shared = [
  FeedItem(
    itinerary: _itinerary(
      id: 'shared-new',
      title: 'Amina Tokyo run',
      ownerId: 'amina',
      createdAt: DateTime.utc(2026, 8, 12),
      stops: 5,
    ),
    owner: const FeedOwner(
      userId: 'amina',
      username: 'amina',
      displayName: 'Amina K.',
    ),
  ),
  FeedItem(
    itinerary: _itinerary(
      id: 'shared-old',
      title: 'Ben Oslo weekend',
      ownerId: 'ben',
      createdAt: DateTime.utc(2026, 8, 1),
      stops: 2,
    ),
    owner: const FeedOwner(userId: 'ben', username: 'ben'),
  ),
];

class _FakeRepo extends ItineraryRepository {
  _FakeRepo({this.sharedThrows = false}) : super(Dio());

  final bool sharedThrows;

  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async =>
      _mine;

  @override
  Future<List<FeedItem>> getSharedWithMe({bool forceRefresh = false}) async {
    if (sharedThrows) throw Exception('shared-with-me is down');
    return _shared;
  }
}

class _EmptySharedRepo extends _FakeRepo {
  @override
  Future<List<FeedItem>> getSharedWithMe({bool forceRefresh = false}) async =>
      const [];
}

/// No trips on either list — no summary pills, whose labels outgrow a phone
/// in the test font, where every character is 1 em wide.
class _NoTripsRepo extends _EmptySharedRepo {
  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async =>
      const [];
}

/// Mine: a trip whose author set a recommended time to spend (3 days) and one
/// that did not (two stops: two hours, computed).
class _RecommendedTimeRepo extends _EmptySharedRepo {
  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async =>
      [
        _itinerary(
          id: 'set',
          title: 'Set',
          ownerId: 'me',
          createdAt: DateTime.utc(2026, 8, 2),
          stops: 2,
        ).copyWith(recommendedDurationMin: 3 * 24 * 60),
        _itinerary(
          id: 'unset',
          title: 'Unset',
          ownerId: 'me',
          createdAt: DateTime.utc(2026, 8, 1),
          stops: 2,
        ),
      ];
}

/// Holds the shared list open until the test completes [gate], so the loading
/// branch can be asserted without a real delay.
class _PendingSharedRepo extends _FakeRepo {
  _PendingSharedRepo(this.gate);

  final Completer<List<FeedItem>> gate;

  @override
  Future<List<FeedItem>> getSharedWithMe({bool forceRefresh = false}) =>
      gate.future;
}

Future<void> _pump(
  WidgetTester tester, {
  ItineraryRepository? repo,
  bool settle = true,
  double width = 1200,
  Locale? locale,
}) async {
  // Tall enough that every card lays out at once — a ListView never builds its
  // off-screen children, so a findsNothing could otherwise pass for the wrong
  // reason.
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // A real router, because every card's onTap is a context.push. Without
  // onLongPress the tap recognizer wins the arena on pointer-up whatever the
  // press duration, so the shared-card test navigates rather than no-opping —
  // which is the point: it opens the trip, it does not offer to delete it.
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const ItineraryListScreen()),
      GoRoute(
        path: '/itineraries/:id',
        builder: (_, s) => Scaffold(body: Text('detail ${s.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  // pumpAndSettle would hang on a Completer that has not been completed yet.
  if (settle) await tester.pumpAndSettle();
}

Rect _title(WidgetTester tester, String text) =>
    tester.getRect(find.text(text));

Rect _filter(WidgetTester tester) =>
    tester.getRect(find.byType(SegmentedButton<ItineraryScope>));

Rect _newItinerary(WidgetTester tester) =>
    tester.getRect(find.byType(FloatingActionButton));

Future<void> _selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('scope filter', () {
    testWidgets('All merges both lists newest-first', (tester) async {
      await _pump(tester);

      expect(find.byType(ItinerarySummaryCard), findsNWidgets(3));
      expect(find.byType(SharedItineraryCard), findsNWidgets(2));

      // 12 Aug (shared) → 10 Aug (mine) → 1 Aug (shared): interleaved, which a
      // plain concatenation would not produce.
      final titles = tester
          .widgetList<ItinerarySummaryCard>(find.byType(ItinerarySummaryCard))
          .map((c) => c.itinerary.title)
          .toList();
      expect(titles,
          ['Amina Tokyo run', 'My Lisbon trip', 'Ben Oslo weekend']);
    });

    testWidgets('Mine shows only owned trips', (tester) async {
      await _pump(tester);
      await _selectScope(tester, 'Mine');

      expect(find.byType(SharedItineraryCard), findsNothing);
      expect(find.text('My Lisbon trip'), findsOneWidget);
      expect(find.text('Amina Tokyo run'), findsNothing);
    });

    testWidgets('Shared shows only granted trips, with attribution',
        (tester) async {
      await _pump(tester);
      await _selectScope(tester, 'Shared');

      expect(find.byType(SharedItineraryCard), findsNWidgets(2));
      expect(find.text('My Lisbon trip'), findsNothing);
      // A restricted trip is in no feed and no search, so whose it is has to be
      // on the card itself.
      expect(find.text('Amina K.'), findsOneWidget);
      expect(find.text('@amina'), findsOneWidget);
      // No display name set — the handle carries the title line instead.
      expect(find.text('@ben'), findsOneWidget);
      expect(find.text('Editor'), findsNWidgets(2));
    });
  });

  group('the delete gesture is owner-only', () {
    testWidgets('long-pressing an owned trip opens the confirm dialog',
        (tester) async {
      await _pump(tester);

      await tester.longPress(find.text('My Lisbon trip'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this itinerary?'), findsOneWidget);
    });

    testWidgets('long-pressing a shared trip does nothing', (tester) async {
      await _pump(tester);

      await tester.longPress(find.text('Amina Tokyo run'));
      await tester.pumpAndSettle();

      // An editor cannot delete, so offering the dialog would only earn a 403
      // after they had typed the trip's title into it.
      expect(find.text('Delete this itinerary?'), findsNothing);
    });
  });

  group('summary pills follow the filter', () {
    testWidgets('totals re-count when the scope changes', (tester) async {
      await _pump(tester);

      // All: 3 trips, 3 + 5 + 2 stops.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);

      await _selectScope(tester, 'Mine');
      // Mine: 1 trip, 3 stops. Both pills now read against the owned trip only.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await _selectScope(tester, 'Shared');
      // Shared: 2 trips, 7 stops.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });
  });

  group('a trip\'s length', () {
    testWidgets(
        'a card shows the author\'s minimum as "3d+" and the computed length '
        'unmarked; the total counts each its own way and is a minimum', (
      tester,
    ) async {
      await _pump(tester, repo: _RecommendedTimeRepo());

      // The "Set" card, and the travelled pill: 3 days + 2 hours = 3d, at least.
      expect(find.text('3d+'), findsNWidgets(2));
      // The "Unset" card, by its stops.
      expect(find.text('2h'), findsOneWidget);
    });
  });

  group('empty and failed states', () {
    testWidgets('Shared gets its own empty copy', (tester) async {
      await _pump(tester, repo: _EmptySharedRepo());
      await _selectScope(tester, 'Shared');

      expect(find.text('No trips shared with you.'), findsOneWidget);
      // The generic "tap + to create" would be wrong here — creating a trip
      // does not populate this list.
      expect(find.text('Tap + to create your first trip.'), findsNothing);
    });

    testWidgets('a dead shared-with-me call still renders Mine',
        (tester) async {
      await _pump(tester, repo: _FakeRepo(sharedThrows: true));
      await _selectScope(tester, 'Mine');

      expect(find.text('My Lisbon trip'), findsOneWidget);
      expect(find.byType(ItinerarySummaryCard), findsOneWidget);
    });

    testWidgets(
        'Given shared-with-me failed, When the error shows on All, '
        'Then the scope selector is still on screen', (tester) async {
      await _pump(tester, repo: _FakeRepo(sharedThrows: true));

      // The escape hatch has to survive the failure. Replacing the whole screen
      // with the error would take the control with it and strand the user on a
      // scope they cannot leave.
      expect(find.byType(SegmentedButton<ItineraryScope>), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('on a wide window', () {
    // The test font draws every character 1 em wide, about twice DM Sans:
    // Chinese labels are what fit beside the title in a 600 px column here.
    testWidgets(
        'Given room for the title and the filter, Then they share a row, the '
        'filter against the column\'s end', (tester) async {
      await _pump(tester, locale: const Locale('zh'));

      final title = _title(tester, '我的行程');
      final filter = _filter(tester);
      expect(filter.center.dy, moreOrLessEquals(title.center.dy, epsilon: 1));
      // The column is 600 px centred on 1200: 300 to 900, inset 16.
      expect(title.left, 316);
      expect(filter.right, 900 - 16);
    });

    testWidgets(
        'Given no room beside the title, Then the filter takes its own row '
        'under it, as wide as the column — the phone layout', (tester) async {
      await _pump(tester, width: 390, repo: _NoTripsRepo());

      final title = _title(tester, 'My Itineraries');
      final filter = _filter(tester);
      expect(filter.top, greaterThanOrEqualTo(title.bottom));
      expect(filter.left, 16);
      expect(filter.width, 390 - 32);
    });

    testWidgets(
        'Given room beside the list, Then New itinerary stands at the '
        'screen\'s far right, off the list', (tester) async {
      await _pump(tester, width: 1440);

      expect(_newItinerary(tester).right, 1440 - 16);
      expect(_newItinerary(tester).left, greaterThan(1020));
    });

    for (final (width, columnEnd) in [(800.0, 700.0), (390.0, 390.0)]) {
      testWidgets(
          'Given no room beside the list at ${width.toInt()} px, Then New '
          'itinerary stands at the list\'s corner, as on a phone',
          (tester) async {
        await _pump(tester, width: width, repo: _NoTripsRepo());

        expect(_newItinerary(tester).right, columnEnd - 16);
      });
    }
  });

  group('loading', () {
    testWidgets(
        'Given both lists are still in flight, When the screen builds, '
        'Then the loader shows and the scope selector is already usable',
        (tester) async {
      final gate = Completer<List<FeedItem>>();
      await _pump(tester, repo: _PendingSharedRepo(gate), settle: false);
      await tester.pump(); // one frame: enough to build, not to resolve

      expect(find.byType(NTripiItineraryLoader), findsOneWidget);
      expect(find.byType(SegmentedButton<ItineraryScope>), findsOneWidget);
      // Mine has resolved, but All is gated on the slower list, so no cards yet.
      expect(find.byType(ItinerarySummaryCard), findsNothing);

      gate.complete(_shared);
      await tester.pumpAndSettle();

      expect(find.byType(NTripiItineraryLoader), findsNothing);
      expect(find.byType(ItinerarySummaryCard), findsNWidgets(3));
    });

    testWidgets(
        'Given only the shared list is in flight, When Mine is selected, '
        'Then Mine renders without waiting for it', (tester) async {
      final gate = Completer<List<FeedItem>>();
      await _pump(tester, repo: _PendingSharedRepo(gate), settle: false);
      await tester.pump();

      await _selectScope(tester, 'Mine');

      // Mine must not be held hostage by the other endpoint.
      expect(find.byType(NTripiItineraryLoader), findsNothing);
      expect(find.text('My Lisbon trip'), findsOneWidget);

      gate.complete(_shared);
      await tester.pumpAndSettle();
    });
  });
}
