// test/widgets/order_by_distance_test.dart — Order by distance on the trip
// page, in arrange mode.
//
// The button is there from three tracks and works out nothing until it is
// tapped. A tap that finds no better order says why; otherwise the sheet asks
// only what changes the answer — where the trip starts, where it ends, the
// transit segments — and says the start or the end stays when no answer
// moves it. The suggestion is shown read-only under a
// bar whose Save saves it at once — one request, no second question about
// transit, nothing downloaded after — and whose Cancel leaves arrange mode as
// it was. While the order is worked out every other button waits and a Cancel
// stops it; Back over any of it ends Order by distance, and only that.
//
// Stops sit on the equator, where 0.01° of longitude is about 1.1 km.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/arrange_trip_view.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/order_by_distance_sheet.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/order_by_distance_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/translation/domain/translation.dart';
import 'package:ntripi/features/translation/providers/translation_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

import '../support/held_claim.dart';
import '../support/recording_dio.dart';
import '../support/trip_json.dart';

final _reorder = itineraryReorderEndpoint(kTripId);

/// A one-stop track [id] whose stop [name] sits at longitude [lng].
Map<String, dynamic> _at(String id, String name, double lng, String rank) =>
    trackJson(id, [stopJson('$id-s', trackId: id, placeName: name, lat: 0, lng: lng)],
        rank: rank);

/// A one-stop track picked from Google: a place ID and no coordinates.
Map<String, dynamic> _google(String id, String name, String rank) => trackJson(
      id,
      [
        {
          ...stopJson('$id-s', trackId: id, placeName: name),
          'place_source': 'google',
          'google_place_id': 'ChIJ$id-place',
        },
      ],
      rank: rank,
    );

/// Hotel, Museum (far), Market (near), Beach: the end stays Beach, and the
/// shortest way there is Hotel → Market → Museum → Beach whatever the end.
Map<String, dynamic> _scrambled() => tripJson(tracks: [
      _at('t1', 'Hotel', 0.00, 'a'),
      _at('t2', 'Museum', 0.03, 'b'),
      _at('t3', 'Market', 0.01, 'c'),
      _at('t4', 'Beach', 0.04, 'd'),
    ]);

class _Owner extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-1',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

/// The owner's trip page in edit mode (this device holds the claim).
Future<AppLocalizations> _pump(
  WidgetTester tester,
  RecordingDio api,
  Map<String, dynamic> trip, {
  Stream<bool>? online,
  OrderByDistanceSolver? solver,
}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  api.adapter.onGet(
      itineraryEndpoint(kTripId), (server) => server.reply(200, trip));
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      itineraryRepositoryProvider
          .overrideWithValue(ItineraryRepository(api.dio)),
      editLockProvider.overrideWith2(HeldClaim.new),
      myProfileProvider.overrideWith(_Owner.new),
      isOnlineProvider.overrideWith((ref) => online ?? Stream.value(true)),
      translationConfigProvider
          .overrideWith((ref) async => TranslationConfig.disabled),
      if (solver != null) orderByDistanceSolverProvider.overrideWithValue(solver),
    ],
    child: MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ItineraryDetailScreen(itineraryId: kTripId),
    ),
  ));
  await tester.pumpAndSettle();
  return lookupAppLocalizations(const Locale('en'));
}

Future<void> _arrange(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byTooltip(l10n.arrangeStops));
  await tester.pumpAndSettle();
}

Future<void> _orderByDistance(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.orderByDistance));
  await tester.pumpAndSettle();
}

/// The rows arrange mode shows, by track id (a new track's local key).
List<String> _rows(WidgetTester tester) => [
      for (final r in tester
          .widget<ArrangeTripView>(find.byType(ArrangeTripView))
          .arrangement
          .rows)
        r.key,
    ];

/// A sheet section, by the label SectionLabel uppercases when it draws it.
Finder _section(String label) =>
    find.byWidgetPredicate((w) => w is SectionLabel && w.label == label);

Finder get _barSave => find.descendant(
      of: find.byType(SuggestedOrderBar),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );

FilledButton _sheetSuggest(WidgetTester tester, AppLocalizations l10n) =>
    tester.widget<FilledButton>(find.ancestor(
      of: find.text(l10n.orderByDistanceSuggest),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ));

void _answersSave(RecordingDio api, Map<String, dynamic> answer) =>
    api.adapter.onPost(
      _reorder,
      (server) => server.reply(200, answer),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
    );

/// Counts the solver's calls on the way to the real one.
class _CountingSolver {
  int calls = 0;

  Future<DistanceOrderChoices?> call(
    TripArrangement arrangement,
    List<TransitSegment> segments, {
    bool Function()? isCancelled,
  }) {
    calls++;
    return orderByDistanceChoices(arrangement, segments,
        isCancelled: isCancelled);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets(
      'the button is in arrange mode from three tracks, and nothing is worked '
      'out before it is tapped', (tester) async {
    final api = RecordingDio();
    final solver = _CountingSolver();
    final l10n = await _pump(tester, api, _scrambled(), solver: solver.call);
    await _arrange(tester, l10n);

    expect(find.byType(OrderByDistanceButton), findsOneWidget);
    // A move re-renders the arrangement; still nothing is worked out.
    await tester.tap(find.descendant(
        of: find.byType(ArrangeTripView), matching: find.text('Beach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.arrangeNewTrackHere).first);
    await tester.pumpAndSettle();
    expect(solver.calls, 0);

    await _orderByDistance(tester, l10n);
    expect(solver.calls, 1);
  });

  testWidgets('two tracks offer no Order by distance', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(
        tester,
        api,
        tripJson(tracks: [
          _at('t1', 'Hotel', 0.00, 'a'),
          _at('t2', 'Museum', 0.03, 'b'),
        ]));
    await _arrange(tester, l10n);
    expect(find.byType(ArrangeTripView), findsOneWidget);
    expect(find.byType(OrderByDistanceButton), findsNothing);
  });

  testWidgets('a trip already in order says so, and changes nothing',
      (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(
        tester,
        api,
        tripJson(tracks: [
          _at('t1', 'Hotel', 0.00, 'a'),
          _at('t2', 'Market', 0.01, 'b'),
          _at('t3', 'Museum', 0.03, 'c'),
          _at('t4', 'Beach', 0.04, 'd'),
        ]));
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);

    expect(find.text(l10n.orderByDistanceAlreadyInOrder), findsOneWidget);
    expect(find.byType(SuggestedOrderBar), findsNothing);
    expect(_rows(tester), ['t1', 't2', 't3', 't4']);
  });

  testWidgets('a trip of Google picks says how few tracks have a saved '
      'location', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(
        tester,
        api,
        tripJson(tracks: [
          _google('t1', 'Hotel', 'a'),
          _google('t2', 'Museum', 'b'),
          _google('t3', 'Market', 'c'),
          _google('t4', 'Beach', 'd'),
        ]));
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);

    expect(find.text(l10n.orderByDistanceTooFewLocated(0, 4)), findsOneWidget);
    expect(find.byType(SuggestedOrderBar), findsNothing);
  });

  testWidgets(
      'with nothing to ask, the suggestion shows at once, read-only; Save '
      'sends it in one request, with no question and nothing downloaded '
      'after', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _scrambled());
    _answersSave(
        api,
        tripAnswer(tripJson(updatedAt: kSavedAt, tracks: [
          _at('t1', 'Hotel', 0.00, 'a'),
          _at('t3', 'Market', 0.01, 'b'),
          _at('t2', 'Museum', 0.03, 'c'),
          _at('t4', 'Beach', 0.04, 'd'),
        ])));
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);

    expect(find.byType(BottomSheet), findsNothing, reason: 'nothing to ask');
    expect(find.text(l10n.suggestedOrderTitle), findsOneWidget);
    expect(find.text(l10n.suggestedOrderMoved(1, 4)), findsOneWidget);
    expect(_rows(tester), ['t1', 't3', 't2', 't4']);
    // Market moved up from 3rd; Museum only made room.
    expect(find.text(l10n.arrangeWasNumber(3)), findsOneWidget);
    expect(find.text(l10n.arrangeWasNumber(2)), findsNothing);
    // The header's ✕ and Save give way to the bar's.
    expect(find.byTooltip(l10n.cancel), findsNothing);
    expect(find.text(l10n.arrangeHint), findsNothing);
    // Read-only: a tap picks nothing.
    await tester.tap(find.descendant(
        of: find.byType(ArrangeTripView), matching: find.text('Beach')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text(l10n.arrangeMovingStop('Beach')), findsNothing);

    api.sent.clear();
    await tester.tap(_barSave);
    await tester.pumpAndSettle();

    expect(api.lines, ['POST $_reorder']);
    expect(api.sent.single.data, {
      'layout': [
        {'track_id': 't1', 'stop_ids': ['t1-s']},
        {'track_id': 't3', 'stop_ids': ['t3-s']},
        {'track_id': 't2', 'stop_ids': ['t2-s']},
        {'track_id': 't4', 'stop_ids': ['t4-s']},
      ],
    });
    expect(find.byType(ArrangeTripView), findsNothing);
    expect(find.text(l10n.orderSavedMessage), findsOneWidget);
  });

  testWidgets(
      'the sheet asks where the trip ends when that changes the answer, and '
      'Suggest waits for a choice that changes the order', (tester) async {
    final api = RecordingDio();
    // Kept last, Beach is already reached the shortest way; free, the trip
    // ends at Museum instead.
    final l10n = await _pump(
        tester,
        api,
        tripJson(tracks: [
          _at('t1', 'Hotel', 0.00, 'a'),
          _at('t2', 'Market', 0.01, 'b'),
          _at('t3', 'Museum', 0.03, 'c'),
          _at('t4', 'Beach', 0.02, 'd'),
        ]));
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);

    expect(_section(l10n.orderByDistanceEndTitle), findsOneWidget);
    expect(_section(l10n.orderByDistanceLegsTitle), findsNothing,
        reason: 'no transit segment to keep or delete');
    expect(find.text(l10n.orderByDistanceStartsAt('Hotel')), findsOneWidget);
    expect(find.text(l10n.orderByDistanceEndAtLast('Beach')), findsOneWidget);
    expect(find.text(l10n.orderByDistanceNoChange), findsOneWidget);
    expect(_sheetSuggest(tester, l10n).onPressed, isNull);

    await tester.tap(find.text(l10n.orderByDistanceEndAnywhere));
    await tester.pumpAndSettle();
    expect(find.text(l10n.orderByDistanceWouldEndAt('Museum')), findsOneWidget);
    expect(find.text(l10n.orderByDistanceNoChange), findsNothing);
    await tester.tap(find.text(l10n.orderByDistanceSuggest));
    await tester.pumpAndSettle();

    expect(_rows(tester), ['t1', 't2', 't4', 't3']);
    expect(find.byType(SuggestedOrderBar), findsOneWidget);
  });

  testWidgets(
      'the sheet asks where the trip starts when that changes the answer, says '
      'the end stays, and Suggest waits for a start that changes the order',
      (tester) async {
    final api = RecordingDio();
    // Market, the first track, sits between the others: kept first, it is
    // already left the shortest way; free, the trip starts at Hotel. Beach is
    // the far end whichever way it starts.
    final l10n = await _pump(
        tester,
        api,
        tripJson(tracks: [
          _at('t1', 'Market', 0.02, 'a'),
          _at('t2', 'Hotel', 0.00, 'b'),
          _at('t3', 'Museum', 0.01, 'c'),
          _at('t4', 'Gallery', 0.03, 'd'),
          _at('t5', 'Beach', 0.04, 'e'),
        ]));
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);

    expect(_section(l10n.orderByDistanceStartTitle), findsOneWidget);
    expect(_section(l10n.orderByDistanceEndTitle), findsNothing);
    expect(find.text(l10n.orderByDistanceEndsAt('Beach')), findsOneWidget);
    expect(find.text(l10n.orderByDistanceStartsAt('Market')), findsNothing);
    expect(
        find.text(l10n.orderByDistanceStartAtFirst('Market')), findsOneWidget);
    expect(find.text(l10n.orderByDistanceWouldStartAt('Hotel')), findsOneWidget);
    expect(find.text(l10n.orderByDistanceNoChange), findsOneWidget);
    expect(_sheetSuggest(tester, l10n).onPressed, isNull);

    await tester.tap(find.text(l10n.orderByDistanceStartAnywhere));
    await tester.pumpAndSettle();
    expect(find.text(l10n.orderByDistanceNoChange), findsNothing);
    await tester.tap(find.text(l10n.orderByDistanceSuggest));
    await tester.pumpAndSettle();

    expect(_rows(tester), ['t2', 't3', 't1', 't4', 't5']);
    // The first track is the one to move by hand.
    expect(find.text(l10n.arrangeWasNumber(1)), findsOneWidget);
    expect(find.text(l10n.suggestedOrderMoved(1, 5)), findsOneWidget);
  });

  testWidgets(
      'a transit segment the shortest order would break is asked about; '
      'deleting it is named in the preview and Save asks nothing more',
      (tester) async {
    final api = RecordingDio();
    // Museum → Market is a leg; Museum is far, Market near the start.
    final l10n = await _pump(
        tester,
        api,
        tripJson(
          tracks: [
            _at('t1', 'Hotel', 0.00, 'a'),
            _at('t2', 'Museum', 0.05, 'b'),
            _at('t3', 'Market', 0.01, 'c'),
            _at('t4', 'Beach', 0.02, 'd'),
          ],
          segments: [segmentJson('seg', 't2-s', 't3-s')],
        ));
    _answersSave(api, tripAnswer(tripJson(updatedAt: kSavedAt, tracks: [])));
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);

    expect(_section(l10n.orderByDistanceLegsTitle), findsOneWidget);
    expect(_sheetSuggest(tester, l10n).onPressed, isNull,
        reason: 'kept, and ending at Beach, nothing can move');
    await tester.tap(find.text(l10n.orderByDistanceBreakLegs));
    await tester.pumpAndSettle();
    expect(find.text(l10n.transitSegmentsWillBeDeleted(1)), findsOneWidget);
    await tester.tap(find.text(l10n.orderByDistanceSuggest));
    await tester.pumpAndSettle();

    expect(_rows(tester), ['t1', 't3', 't2', 't4']);
    // Arrange mode's own banner names the segment the save deletes.
    expect(find.text(l10n.transitSegmentsWillBeDeleted(1)), findsOneWidget);

    api.sent.clear();
    await tester.tap(_barSave);
    await tester.pumpAndSettle();
    expect(find.text(l10n.reorderOrphanTitle), findsNothing);
    expect(api.lines, ['POST $_reorder']);
    expect((api.sent.single.data as Map)['segments_to_delete'], ['seg']);
  });

  testWidgets(
      'Cancel leaves arrange mode exactly as it was, the moves made before '
      'included', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(
        tester,
        api,
        tripJson(tracks: [
          _at('t1', 'Hotel', 0.00, 'a'),
          trackJson('t2', [
            stopJson('t2-a', trackId: 't2', placeName: 'Museum', lat: 0, lng: 0.03),
            stopJson('t2-b', trackId: 't2', placeName: 'Gallery', lat: 0, lng: 0.031),
          ], rank: 'b'),
          _at('t3', 'Market', 0.01, 'c'),
          _at('t4', 'Beach', 0.04, 'd'),
        ]));
    await _arrange(tester, l10n);
    // Gallery gets a track of its own, at the end.
    await tester.tap(find.descendant(
        of: find.byType(ArrangeTripView), matching: find.text('Gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.arrangeNewTrackHere).last);
    await tester.pumpAndSettle();
    final before = _rows(tester);
    expect(before, ['t1', 't2', 't3', 't4', 'new:0']);

    await _orderByDistance(tester, l10n);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tap(find.text(l10n.orderByDistanceSuggest));
      await tester.pumpAndSettle();
    }
    expect(find.byType(SuggestedOrderBar), findsOneWidget);
    expect(_rows(tester), isNot(before));

    await tester.tap(find.descendant(
        of: find.byType(SuggestedOrderBar), matching: find.text(l10n.cancel)));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestedOrderBar), findsNothing);
    expect(_rows(tester), before);
    expect(find.byType(OrderByDistanceButton), findsOneWidget);
  });

  testWidgets('Back over the preview ends the preview, not arrange mode',
      (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _scrambled());
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);
    expect(find.byType(SuggestedOrderBar), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SuggestedOrderBar), findsNothing);
    expect(find.byType(ArrangeTripView), findsOneWidget);
    expect(_rows(tester), ['t1', 't2', 't3', 't4']);
    expect(api.sent.where((o) => o.method == 'POST'), isEmpty);
  });

  testWidgets(
      'while the order is worked out the rows take no touch, and Back stops '
      'it; an answer that lands after is dropped', (tester) async {
    final api = RecordingDio();
    final pending = Completer<DistanceOrderChoices?>();
    bool Function()? cancelled;
    late TripArrangement asked;
    final l10n = await _pump(tester, api, _scrambled(),
        solver: (arrangement, segments, {isCancelled}) {
      asked = arrangement;
      cancelled = isCancelled;
      return pending.future;
    });
    await _arrange(tester, l10n);
    await tester.tap(find.text(l10n.orderByDistance));
    await tester.pump();

    expect(find.text(l10n.orderByDistanceWorking), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(ArrangeTripView), matching: find.text('Beach')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.text(l10n.arrangeMovingStop('Beach')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(l10n.orderByDistanceWorking), findsNothing);
    expect(find.byType(ArrangeTripView), findsOneWidget);
    expect(cancelled!(), isTrue);

    pending.complete(await orderByDistanceChoices(asked, const []));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestedOrderBar), findsNothing);
  });

  testWidgets(
      'Given the order is being worked out, Then every other button waits and '
      'a Cancel is offered; When Cancel is tapped, Then the work stops and '
      'arrange mode is as it was', (tester) async {
    final api = RecordingDio();
    final pending = Completer<DistanceOrderChoices?>();
    bool Function()? cancelled;
    late TripArrangement asked;
    final l10n = await _pump(tester, api, _scrambled(),
        solver: (arrangement, segments, {isCancelled}) {
      asked = arrangement;
      cancelled = isCancelled;
      return pending.future;
    });
    await _arrange(tester, l10n);
    await tester.tap(find.text(l10n.orderByDistance));
    await tester.pump();

    final cancel = find.descendant(
        of: find.byType(OrderByDistanceButton),
        matching: find.text(l10n.cancel));
    expect(find.text(l10n.orderByDistanceWorking), findsOneWidget);
    expect(cancel, findsOneWidget);
    // The header's ✕ and Save wait for the answer.
    expect(
        tester
            .widget<IconButton>(find.ancestor(
                of: find.byTooltip(l10n.cancel),
                matching: find.byType(IconButton)))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<FilledButton>(find
                .ancestor(
                    of: find.text(l10n.save),
                    matching: find.byWidgetPredicate((w) => w is FilledButton))
                .first)
            .onPressed,
        isNull);

    await tester.tap(cancel);
    await tester.pump();
    expect(cancelled!(), isTrue);
    expect(find.text(l10n.orderByDistanceWorking), findsNothing);
    expect(cancel, findsNothing);
    expect(find.text(l10n.orderByDistance), findsOneWidget);
    expect(_rows(tester), ['t1', 't2', 't3', 't4']);

    // An answer that lands afterwards is dropped.
    pending.complete(await orderByDistanceChoices(asked, const []));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestedOrderBar), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('offline, the preview cannot be saved', (tester) async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    online.add(true);
    final api = RecordingDio();
    final l10n =
        await _pump(tester, api, _scrambled(), online: online.stream);
    await _arrange(tester, l10n);
    await _orderByDistance(tester, l10n);
    expect(tester.widget<FilledButton>(_barSave).onPressed, isNotNull);

    online.add(false);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_barSave).onPressed, isNull);
  });
}
