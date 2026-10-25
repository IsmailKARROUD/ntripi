// test/widgets/trip_reload_keeps_content_test.dart — pulling the trip page
// keeps the trip on screen.
//
// Pull-to-refresh used to swap the whole trip for the full-screen loader until
// the new copy came back, rebuilding it with every "view more" closed, and a
// failed reload replaced it with the error view. Now the trip stays mounted for
// the whole reload, the pull's own spinner is the only sign of it, an answer
// replaces the trip in place, and a failure leaves it and says so in a
// SnackBar.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

import '../support/recording_dio.dart';
import '../support/trip_json.dart';

/// Long enough to fold into two lines behind "view more".
final _notes = List.filled(12, 'Take the cliff path at low tide.').join(' ');

Map<String, dynamic> _trip(String title) => tripJson(
      title: title,
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

void main() {
  // Past the first-visit long-press tip, which would take the first tap.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets(
      'a pull keeps the trip and its open "view more" on screen; a failed one '
      'keeps it too and says why', (tester) async {
    // Tall enough that the stop card is built and on screen.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = RecordingDio();
    final trip = itineraryEndpoint(kTripId);
    api.adapter.onGet(trip, (server) => server.reply(200, _trip('Before')));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        itineraryRepositoryProvider
            .overrideWithValue(ItineraryRepository(api.dio)),
        myProfileProvider.overrideWith(_Viewer.new),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ItineraryDetailScreen(itineraryId: kTripId),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsWidgets);

    await tester.tap(find.text('... view more'));
    await tester.pumpAndSettle();
    expect(find.text('view less'), findsOneWidget);

    int tripGets() =>
        api.sent.where((o) => o.method == 'GET' && o.path == trip).length;

    /// A pull past the indicator's arming distance (a quarter of the view),
    /// left with its reload's request out.
    Future<void> pull() async {
      final sent = tripGets();
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 1500), 1000);
      await tester.pump();
      // The indicator snaps to its armed position and calls onRefresh.
      await tester.pump(const Duration(seconds: 1));
      // The request reaches the wire a few frames after onRefresh starts.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tripGets(), sent + 1, reason: 'the pull sent its reload');
    }

    // ── A reload that answers ────────────────────────────────────────────
    api.adapter.onGet(trip, (server) => server.reply(200, _trip('After')));
    var reply = api.hold(trip);
    await pull();

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
    api.adapter.onGet(
      trip,
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: trip),
          type: DioExceptionType.receiveTimeout,
        ),
      ),
    );
    reply = api.hold(trip);
    await pull();
    expect(find.byType(NTripiRouteLoader), findsNothing);

    reply.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('After'), findsWidgets);
    expect(find.text('view less'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(
          'No internet connection. Please check your network and try again.'),
      findsOneWidget,
    );
  });
}
