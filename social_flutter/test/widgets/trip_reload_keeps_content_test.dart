// test/widgets/trip_reload_keeps_content_test.dart — pulling the trip page
// keeps the trip on screen.
//
// Pull-to-refresh used to swap the whole trip for the full-screen loader until
// the new copy came back, rebuilding it with every "view more" closed, and a
// failed reload replaced it with the error view. Now the trip stays mounted for
// the whole reload, the pull's own spinner is the only sign of it, an answer
// replaces the trip in place, and a failure leaves it and says so in a
// SnackBar. A trip with a cover drops it from the image cache first, so a
// cover replaced under the same key shows — and that step can never stop the
// reload or escape into the pull.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/cache/image_cache.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _offline =
    'No internet connection. Please check your network and try again.';

/// Long enough to fold into two lines behind "view more".
final _notes = List.filled(12, 'Take the cliff path at low tide.').join(' ');

final _trip = itineraryEndpoint(kTripId);

Map<String, dynamic> _tripBody(String title, {String? coverUrl}) => tripJson(
      title: title,
      coverUrl: coverUrl,
      tracks: [
        trackJson('t1', [stopJson('stop-1', notes: _notes)]),
      ],
    );

/// Someone else's trip: read mode, as most pulls are.
class _Viewer extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-2',
        username: 'reader',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

/// The trip page on [api], loaded with [first] (answered with [status]).
Future<void> _pumpTrip(
  WidgetTester tester,
  RecordingDio api,
  Map<String, dynamic> first, {
  int status = 200,
  ImageCacheEviction? eviction,
}) async {
  // Tall enough that the stop card is built and on screen.
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  api.adapter.onGet(_trip, (server) => server.reply(status, first));
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      itineraryRepositoryProvider
          .overrideWithValue(ItineraryRepository(api.dio)),
      myProfileProvider.overrideWith(_Viewer.new),
      // The real eviction, through an evictor the test chooses: the image
      // cache itself cannot answer in a test.
      imageCacheEvictionProvider.overrideWithValue(
          eviction ?? ImageCacheEviction(evictOne: (_) async {})),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ItineraryDetailScreen(itineraryId: kTripId),
    ),
  ));
  await tester.pumpAndSettle();
}

int _tripGets(RecordingDio api) =>
    api.sent.where((o) => o.method == 'GET' && o.path == _trip).length;

/// A pull past the indicator's arming distance (a quarter of the view), left
/// with its reload's request out.
Future<void> _pull(WidgetTester tester, RecordingDio api) async {
  final sent = _tripGets(api);
  await tester.fling(
      find.byType(CustomScrollView).first, const Offset(0, 1500), 1000);
  await tester.pump();
  // The indicator snaps to its armed position and calls onRefresh.
  await tester.pump(const Duration(seconds: 1));
  // The request reaches the wire a few frames after onRefresh starts.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_tripGets(api), sent + 1, reason: 'the pull sent its reload');
}

void _timesOut(RecordingDio api) => api.adapter.onGet(
      _trip,
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: _trip),
          type: DioExceptionType.receiveTimeout,
        ),
      ),
    );

void main() {
  // Past the first-visit long-press tip, which would take the first tap.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets(
      'a pull keeps the trip and its open "view more" on screen; a failed one '
      'keeps it too and says why', (tester) async {
    final api = RecordingDio();
    await _pumpTrip(tester, api, _tripBody('Before'));
    expect(find.text('Before'), findsWidgets);

    await tester.tap(find.text('... view more'));
    await tester.pumpAndSettle();
    expect(find.text('view less'), findsOneWidget);

    // ── A reload that answers ────────────────────────────────────────────
    api.adapter.onGet(_trip, (server) => server.reply(200, _tripBody('After')));
    var reply = api.hold(_trip);
    await _pull(tester, api);

    expect(find.byType(NTripiRouteLoader), findsNothing);
    expect(find.text('Before'), findsWidgets);
    expect(find.text('view less'), findsOneWidget,
        reason: 'the stop card was never unmounted');

    reply.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('After'), findsWidgets);
    expect(find.text('Before'), findsNothing);
    expect(find.text('view less'), findsOneWidget,
        reason: 'the answer replaced the trip in place');

    // ── A reload that fails ──────────────────────────────────────────────
    _timesOut(api);
    reply = api.hold(_trip);
    await _pull(tester, api);
    expect(find.byType(NTripiRouteLoader), findsNothing);

    reply.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('After'), findsWidgets);
    expect(find.text('view less'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_offline), findsOneWidget);
  });

  testWidgets(
      'with nothing on screen, Retry shows the loader, then the trip',
      (tester) async {
    final api = RecordingDio();
    await _pumpTrip(
        tester, api, const {'detail': 'Internal Server Error'}, status: 500);
    expect(find.text('Retry'), findsOneWidget);

    api.adapter.onGet(_trip, (server) => server.reply(200, _tripBody('Before')));
    final reply = api.hold(_trip);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(NTripiRouteLoader), findsOneWidget);

    reply.complete();
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsWidgets);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('a trip with a cover', () {
    const cover = 'https://images.example/itineraries/itin-1.jpg';

    // The hero's CachedNetworkImage cannot fetch in a test; that is noise, not
    // what is under test.
    setUp(() {
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
    });

    testWidgets(
        'a pull clears the cover from the image cache, then reloads the trip',
        (tester) async {
      final api = RecordingDio();
      // Each URL cleared, with how many trip GETs had gone out by then.
      final cleared = <({String url, int tripGets})>[];
      await _pumpTrip(
        tester,
        api,
        _tripBody('Before', coverUrl: cover),
        eviction: ImageCacheEviction(
            evictOne: (url) async =>
                cleared.add((url: url, tripGets: _tripGets(api)))),
      );

      api.adapter.onGet(_trip,
          (server) => server.reply(200, _tripBody('After', coverUrl: cover)));
      final reply = api.hold(_trip);
      await _pull(tester, api);
      expect(find.byType(NTripiRouteLoader), findsNothing);
      expect(find.text('Before'), findsWidgets);

      // Cleared first: only the first load's GET had gone out.
      expect(cleared, [(url: cover, tripGets: 1)]);

      reply.complete();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('After'), findsWidgets);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'a pull whose cover cannot be cleared still reloads the trip, '
        'and the cover stays as it was', (tester) async {
      final api = RecordingDio();
      await _pumpTrip(
        tester,
        api,
        _tripBody('Before', coverUrl: cover),
        eviction: ImageCacheEviction(
            evictOne: (_) async => throw const FileSystemException(
                'the image cache could not be opened')),
      );

      api.adapter.onGet(_trip,
          (server) => server.reply(200, _tripBody('After', coverUrl: cover)));
      // _pull checks the reload went out: the failure stopped short of it.
      await _pull(tester, api);
      await tester.pumpAndSettle();

      expect(find.text('After'), findsWidgets);
      // Best-effort: a stale cover is not worth a message.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed pull keeps the trip and says why', (tester) async {
      final api = RecordingDio();
      await _pumpTrip(tester, api, _tripBody('Before', coverUrl: cover));

      _timesOut(api);
      await _pull(tester, api);
      await tester.pumpAndSettle();

      expect(find.text('Before'), findsWidgets);
      expect(find.text(_offline), findsOneWidget);
    });
  });
}
