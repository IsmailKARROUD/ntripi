// test/widgets/arrange_mode_test.dart — arrange mode on the trip page.
//
// The header's one button opens arrange mode: the stop cards give way to rows
// of chips, everything else on the page stops answering, and stops and whole
// tracks move by tap or by drag. Nothing is sent until Save, which carries the
// whole layout — and the transport it breaks — in one request, and adopts the
// answer, so nothing downloads the trip again. Leaving asks before discarding,
// and a save refused for a lost claim keeps the arrangement to save again.
// Every drag ends clean: let go where it was, a stop changes nothing, and after
// any drop nothing is left picked or offered as a target.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/arrange_trip_view.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/edit_lock_banner.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/translation/domain/translation.dart';
import 'package:ntripi/features/translation/providers/translation_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/held_claim.dart';
import '../support/recording_dio.dart';
import '../support/trip_json.dart';

final _reorder = itineraryReorderEndpoint(kTripId);

Map<String, dynamic> _s1() => stopJson('s1', trackId: 't1', placeName: 'Harbour');
Map<String, dynamic> _s2() => stopJson('s2', trackId: 't2', placeName: 'Museum');
Map<String, dynamic> _s3() => stopJson('s3', trackId: 't2', placeName: 'Market');
Map<String, dynamic> _s4() => stopJson('s4', trackId: 't3', placeName: 'Beach');

/// Harbour, then Museum or Market, then Beach.
Map<String, dynamic> _trip({List<Map<String, dynamic>> segments = const []}) =>
    tripJson(
      tracks: [
        trackJson('t1', [_s1()], rank: 'a'),
        trackJson('t2', [_s2(), _s3()], rank: 'b'),
        trackJson('t3', [_s4()], rank: 'c'),
      ],
      segments: segments,
    );

/// What a save answers: the trip as [tracks] now hold it, at a later stamp.
Map<String, dynamic> _answer(List<Map<String, dynamic>> tracks) =>
    tripAnswer(tripJson(updatedAt: kSavedAt, tracks: tracks));

/// Whoever holds the claim now, as a 409 names them.
final _holder = {
  'holder_id': 'user-2',
  'holder_username': 'rafa',
  'holder_display_name': 'Rafa',
  'holder_avatar_url': null,
  'is_you': false,
  'state': 'active',
  'acquired_at': '2026-10-21T10:00:01Z',
  'last_heartbeat_at': '2026-10-21T10:00:01Z',
  'idle_at': '2026-10-21T10:01:31Z',
  'takeover_available_at': '2026-10-21T10:05:01Z',
};

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

/// The owner's trip page, in edit mode (this device holds the claim).
Future<AppLocalizations> _pump(
  WidgetTester tester,
  RecordingDio api,
  Map<String, dynamic> trip,
) async {
  // Tall enough that the whole page is on screen without scrolling.
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
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      translationConfigProvider
          .overrideWith((ref) async => TranslationConfig.disabled),
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

/// Answers the arrangement's save with [answer].
void _answersSave(RecordingDio api, Map<String, dynamic> answer, {int status = 200}) =>
    api.adapter.onPost(
      _reorder,
      (server) => server.reply(status, answer),
      data: Matchers.any,
      queryParameters: {'return': 'itinerary'},
    );

Future<void> _arrange(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byTooltip(l10n.arrangeStops));
  await tester.pumpAndSettle();
}

Finder _inArrangement(Finder finder) =>
    find.descendant(of: find.byType(ArrangeTripView), matching: finder);

Finder get _save => find.ancestor(
      of: find.byIcon(Icons.check_rounded),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_save).onPressed != null;

/// The stops a screen reader hears as selected: the one being moved, which is
/// the one drawn picked.
List<String> _selected(WidgetTester tester) => [
      for (final name in ['Harbour', 'Museum', 'Market', 'Beach'])
        if (isSemantics(isSelected: true).matches(
            tester.getSemantics(_inArrangement(find.text(name))), {}))
          name,
    ];

/// The faded copy a lifted stop leaves in its place.
Finder _fadedCopy(String name) => find.ancestor(
      of: _inArrangement(find.text(name)),
      matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
    );

/// A stop's ⠿ handle, which drags at once.
Finder _handleOf(String name) => find.descendant(
      of: find.ancestor(
        of: _inArrangement(find.text(name)),
        matching: find.byWidgetPredicate((w) => w is LongPressDraggable),
      ),
      matching: find.byIcon(Icons.drag_indicator_rounded),
    );

void main() {
  // Past the first-visit long-press tip, which would take the first tap.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets(
      'the header button opens arrange mode: rows of stops, the rest of the '
      'page inert', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    // Edit mode: the cards carry their buttons, and the hero's ✓ answers.
    expect(find.text(l10n.addParallelStopLabel), findsWidgets);
    expect(find.byIcon(Icons.check_rounded).hitTestable(), findsOneWidget);

    await _arrange(tester, l10n);

    expect(find.text(l10n.arrangeHint), findsOneWidget);
    for (final name in ['Harbour', 'Museum', 'Market', 'Beach']) {
      expect(_inArrangement(find.text(name)), findsOneWidget);
    }
    expect(find.text(l10n.addParallelStopLabel), findsNothing);
    // The hero's ✓ is still drawn but deaf: the one ✓ that answers is Save.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.check_rounded).hitTestable(), findsOneWidget);
    expect(_saveEnabled(tester), isFalse, reason: 'nothing to save yet');
  });

  testWidgets(
      'a stop tapped, then another track tapped, joins that track; Save sends '
      'the layout in one request and downloads nothing after', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    _answersSave(api, _answer([
      trackJson('t1', [_s1(), stopJson('s4', trackId: 't1', placeName: 'Beach')]),
      trackJson('t2', [_s2(), _s3()], rank: 'b'),
    ]));
    await _arrange(tester, l10n);

    await tester.tap(_inArrangement(find.text('Beach')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.arrangeMovingStop('Beach')), findsOneWidget);
    // Harbour's track first among those offering to take it.
    await tester.tap(find.text(l10n.arrangeAddAsAlternative).first);
    await tester.pumpAndSettle();
    expect(_saveEnabled(tester), isTrue);

    api.sent.clear();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(api.lines, ['POST $_reorder']);
    final sent = api.sent.single;
    expect(sent.queryParameters, {'return': 'itinerary'});
    expect(sent.headers[kEditLockHeader], kHeldClaimToken);
    expect(sent.data, {
      'layout': [
        {
          'track_id': 't1',
          'stop_ids': ['s1', 's4'],
        },
        {
          'track_id': 't2',
          'stop_ids': ['s2', 's3'],
        },
      ],
    });
    // Back in edit mode on the answered trip.
    expect(find.byType(ArrangeTripView), findsNothing);
    expect(find.text(l10n.editStopsButton), findsOneWidget);
    expect(find.text(l10n.orderSavedMessage), findsOneWidget);
  });

  testWidgets("a track's number drags the whole track to another place",
      (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    _answersSave(api, _answer([
      trackJson('t3', [_s4()], rank: 'a'),
      trackJson('t1', [_s1()], rank: 'b'),
      trackJson('t2', [_s2(), _s3()], rank: 'c'),
    ]));
    await _arrange(tester, l10n);

    final gesture =
        await tester.startGesture(tester.getCenter(_inArrangement(find.text('3'))));
    await gesture.moveBy(const Offset(0, -30)); // past the slop: it lifts
    await tester.pump();
    // Its own place is no target; the gaps that would move it are.
    await gesture.moveTo(
        tester.getCenter(find.text(l10n.arrangeNewTrackHere).first));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    api.sent.clear();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(api.sent.single.data, {
      'layout': [
        {
          'track_id': 't3',
          'stop_ids': ['s4'],
        },
        {
          'track_id': 't1',
          'stop_ids': ['s1'],
        },
        {
          'track_id': 't2',
          'stop_ids': ['s2', 's3'],
        },
      ],
    });
  });

  testWidgets(
      'a stop held still and let go stays put and unpicked, with nothing '
      'moving under the finger, so a stop tapped next is the only one picked',
      (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    await _arrange(tester, l10n);
    final around = {
      for (final name in ['Harbour', 'Market', 'Beach'])
        name: tester.getRect(_inArrangement(find.text(name))),
    };

    // Museum, the first of its track's two: let go in place, it must not go
    // last. A finger held still still trembles.
    final hold = await tester
        .startGesture(tester.getCenter(_inArrangement(find.text('Museum'))));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await hold.moveBy(const Offset(1, 2));
    await tester.pump();
    expect(_fadedCopy('Museum'), findsOneWidget, reason: 'lifted');
    expect(find.text(l10n.arrangeNewTrackHere), findsNothing);
    for (final MapEntry(key: name, value: rect) in around.entries) {
      expect(tester.getRect(_inArrangement(find.text(name))), rect,
          reason: '$name moved under the finger');
    }
    await hold.up();
    await tester.pumpAndSettle();

    expect(_selected(tester), isEmpty);
    expect(find.text(l10n.arrangeNewTrackHere), findsNothing);
    expect(_saveEnabled(tester), isFalse, reason: 'nothing moved');

    await tester.tap(_inArrangement(find.text('Beach')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.arrangeMovingStop('Beach')), findsOneWidget);
    expect(_selected(tester), ['Beach']);
  });

  testWidgets(
      'a held stop stays lifted while its own track lights up under it, and '
      'dropped on the track it goes last', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    _answersSave(api, _answer([
      trackJson('t1', [_s1()], rank: 'a'),
      trackJson('t2', [_s3(), _s2()], rank: 'b'),
      trackJson('t3', [_s4()], rank: 'c'),
    ]));
    await _arrange(tester, l10n);

    final hold = await tester
        .startGesture(tester.getCenter(_inArrangement(find.text('Museum'))));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await hold.moveBy(const Offset(40, 0)); // under way: the targets open
    await tester.pump();
    // The free end of its own track, which takes its own stop.
    await hold.moveTo(tester.getCenter(_inArrangement(find.text('Museum'))) +
        const Offset(500, 0));
    await tester.pump();
    expect(_fadedCopy('Museum'), findsOneWidget, reason: 'still lifted');
    await hold.up();
    await tester.pumpAndSettle();

    expect(_selected(tester), isEmpty);
    expect(find.text(l10n.arrangeNewTrackHere), findsNothing);

    api.sent.clear();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(api.sent.single.data, {
      'layout': [
        {
          'track_id': 't1',
          'stop_ids': ['s1'],
        },
        {
          'track_id': 't2',
          'stop_ids': ['s3', 's2'],
        },
        {
          'track_id': 't3',
          'stop_ids': ['s4'],
        },
      ],
    });
  });

  testWidgets(
      "a stop dragged by its handle onto another track's stop goes before it, "
      'and the drop leaves nothing picked or offered', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    _answersSave(api, _answer([
      trackJson('t1', [stopJson('s4', trackId: 't1', placeName: 'Beach'), _s1()]),
      trackJson('t2', [_s2(), _s3()], rank: 'b'),
    ]));
    await _arrange(tester, l10n);

    final drag =
        await tester.startGesture(tester.getCenter(_handleOf('Beach')));
    await drag.moveBy(const Offset(0, -30)); // past the slop: it lifts
    await tester.pump();
    await drag.moveTo(tester.getCenter(_inArrangement(find.text('Harbour'))));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(_selected(tester), isEmpty);
    expect(find.text(l10n.arrangeNewTrackHere), findsNothing);
    expect(find.text(l10n.arrangeAddAsAlternative), findsNothing);

    api.sent.clear();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(api.sent.single.data, {
      'layout': [
        {
          'track_id': 't1',
          'stop_ids': ['s4', 's1'],
        },
        {
          'track_id': 't2',
          'stop_ids': ['s2', 's3'],
        },
      ],
    });
  });

  testWidgets(
      'a move that breaks transport is marked at once, confirmed on Save, and '
      'deletes it in the same request', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(
        tester, api, _trip(segments: [segmentJson('seg-1', 's1', 's2')]));
    _answersSave(api, _answer([
      trackJson('t1', [_s1()], rank: 'a'),
      trackJson('t3', [_s4()], rank: 'b'),
      trackJson('t2', [_s2(), _s3()], rank: 'c'),
    ]));
    await _arrange(tester, l10n);
    expect(find.text(l10n.transitSegmentsWillBeDeleted(1)), findsNothing);

    // Track 2 after track 3: Harbour → Museum no longer reaches the next track.
    await tester.tap(_inArrangement(find.text('2')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.arrangeMovingTrack(2)), findsOneWidget);
    await tester.tap(find.text(l10n.arrangeNewTrackHere).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.transitSegmentsWillBeDeleted(1)), findsOneWidget);
    expect(find.text(l10n.segmentToWillBeDeleted('Museum')), findsOneWidget);

    api.sent.clear();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text(l10n.reorderOrphanTitle), findsOneWidget);
    expect(api.sent, isEmpty, reason: 'nothing is sent before the confirmation');

    await tester.tap(find.text(l10n.save).last);
    await tester.pumpAndSettle();

    expect(api.sent.single.data, {
      'layout': [
        {
          'track_id': 't1',
          'stop_ids': ['s1'],
        },
        {
          'track_id': 't3',
          'stop_ids': ['s4'],
        },
        {
          'track_id': 't2',
          'stop_ids': ['s2', 's3'],
        },
      ],
      'segments_to_delete': ['seg-1'],
    });
  });

  testWidgets(
      'leaving with an unsaved arrangement asks first, and discarding sends '
      'nothing', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    await _arrange(tester, l10n);
    // Beach alone in its track: a gap moves the track, here to the front.
    await tester.tap(_inArrangement(find.text('Beach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.arrangeNewTrackHere).first);
    await tester.pumpAndSettle();
    api.sent.clear();

    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.discardChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.discardButton));
    await tester.pumpAndSettle();

    expect(find.byType(ArrangeTripView), findsNothing);
    expect(find.text(l10n.editStopsButton), findsOneWidget);
    expect(api.sent, isEmpty);
  });

  testWidgets(
      'in a narrow column a long name gives way, rather than overflowing its '
      'track, when the track offers itself for a picked stop', (tester) async {
    // The view alone: what is being tested is its own rows, at a width where a
    // chip's 220 px cap is wider than the room its track has.
    final tracks = Itinerary.fromJson(tripJson(tracks: [
      trackJson('t1', [_s1()], rank: 'a'),
      trackJson('t2', [
        stopJson('s2',
            trackId: 't2',
            placeName: 'The Calouste Gulbenkian Museum and its gardens'),
      ], rank: 'b'),
    ])).tracks;
    await tester.pumpWidget(MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280,
            child: SingleChildScrollView(
              child: ArrangeTripView(
                arrangement: TripArrangement.of(tracks),
                segments: const [],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text('Harbour'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.arrangeAddAsAlternative), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back with nothing arranged leaves arrange mode, not edit mode',
      (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    await _arrange(tester, l10n);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(l10n.discardChangesTitle), findsNothing);
    expect(find.byType(ArrangeTripView), findsNothing);
    expect(find.text(l10n.editStopsButton), findsOneWidget);
  });

  testWidgets(
      'a save refused for a lost claim keeps the arrangement, with Save '
      'disabled and the lock banner beside it', (tester) async {
    final api = RecordingDio();
    final l10n = await _pump(tester, api, _trip());
    _answersSave(
      api,
      {'detail': 'edit lock lost', 'code': 'edit_lock_lost', 'lock': _holder},
      status: 409,
    );
    await _arrange(tester, l10n);
    await tester.tap(_inArrangement(find.text('Beach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.arrangeNewTrackHere).first);
    await tester.pumpAndSettle();

    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(find.byType(ArrangeTripView), findsOneWidget);
    expect(find.byType(EditLockBanner), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
    // Still the arrangement made: leaving it asks before discarding.
    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.discardChangesTitle), findsOneWidget);
  });
}
