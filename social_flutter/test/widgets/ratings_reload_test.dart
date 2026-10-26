// test/widgets/ratings_reload_test.dart — pulling the ratings pages.
//
// Both ratings screens draw from `.value`, which an AsyncError still carries,
// and they used to show the error only while no page was loaded: a reload the
// server refused (the trip no longer yours to see) left the reviews on screen
// over it. Now an error is always the answer — the reload keeps the page
// through anything else (ReloadKeepsContent) — and a failed pull keeps the
// reviews and says why.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/dimension_key.dart';
import 'package:ntripi/features/itineraries/presentation/dimension_ratings_screen.dart';
import 'package:ntripi/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _offline =
    'No internet connection. Please check your network and try again.';
const _couldNotLoad = 'Could not load ratings';

final _page = itineraryRatingsEndpoint(kTripId);

/// The page with one review, scored overall and on safety.
Map<String, dynamic> _pageBody(String note) => {
      'rating_avg': 4.0,
      'rating_count': 1,
      'distribution': {'five': 0, 'four': 1, 'three': 0, 'two': 0, 'one': 0},
      'ratings': [
        {
          'score': 4,
          'safety_score': 4,
          'note': note,
          'updated_at': '2026-10-20T10:00:00Z',
          'user': {
            'user_id': 'rater-1',
            'username': 'rater',
            'display_name': 'A Rater',
            'avatar_url': null,
          },
          'id': 'rating-1',
          'moderation_status': 'approved',
        },
      ],
    };

class _Viewer extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'viewer-1',
        username: 'viewer',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

Future<void> _pump(WidgetTester tester, RecordingDio api, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({});

  api.adapter.onGet(_page, (server) => server.reply(200, _pageBody('Lovely walk')));
  // No rating of the viewer's own: the GET answers 404, which reads as none.
  api.adapter.onGet(itineraryMyRatingEndpoint(kTripId),
      (server) => server.reply(404, {'code': 'rating_not_found'}));
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(api.dio)),
      myProfileProvider.overrideWith(_Viewer.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Past the indicator's arming distance: a quarter of the page's height.
Future<void> _pull(WidgetTester tester) async {
  await tester.fling(
      find.byType(RefreshIndicator).first, const Offset(0, 1000), 1000);
  await tester.pumpAndSettle();
}

void _refused(RecordingDio api) => api.adapter.onGet(
      _page,
      (server) => server.reply(403, {
        'detail': "You don't have access to this itinerary",
        'code': 'itinerary_access_denied',
      }),
    );

void _timesOut(RecordingDio api) => api.adapter.onGet(
      _page,
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: _page),
          type: DioExceptionType.receiveTimeout,
        ),
      ),
    );

void main() {
  group('the ratings page', () {
    const screen = RatingsHubScreen(itineraryId: kTripId);

    testWidgets(
        'Given the reviews on screen, When a pull is refused, '
        'Then the error replaces them, and Retry brings them back',
        (tester) async {
      final api = RecordingDio();
      await _pump(tester, api, screen);
      expect(find.textContaining('Lovely walk'), findsOneWidget);

      _refused(api);
      await _pull(tester);

      expect(find.text(_couldNotLoad), findsOneWidget);
      expect(find.textContaining('Lovely walk'), findsNothing);

      // Retry from the error view: the loader, then the page.
      api.adapter.onGet(
          _page, (server) => server.reply(200, _pageBody('Lovely walk')));
      final reply = api.hold(_page);
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(NTripiRouteLoader), findsOneWidget);

      reply.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Lovely walk'), findsOneWidget);
      expect(find.text(_couldNotLoad), findsNothing);
    });

    testWidgets(
        'Given the reviews on screen, When a pull times out, '
        'Then they stay and the reason shows in a SnackBar', (tester) async {
      final api = RecordingDio();
      await _pump(tester, api, screen);

      _timesOut(api);
      await _pull(tester);

      expect(find.textContaining('Lovely walk'), findsOneWidget);
      expect(find.text(_couldNotLoad), findsNothing);
      expect(find.text(_offline), findsOneWidget);
    });
  });

  group('one dimension\'s ratings', () {
    const screen = DimensionRatingsScreen(
        itineraryId: kTripId, dimension: DimensionKey.safety);

    testWidgets(
        'Given the reviews on screen, When a pull is refused, '
        'Then the error replaces them, and Retry brings them back',
        (tester) async {
      final api = RecordingDio();
      await _pump(tester, api, screen);
      expect(find.textContaining('Lovely walk'), findsOneWidget);

      _refused(api);
      await _pull(tester);

      expect(find.text(_couldNotLoad), findsOneWidget);
      expect(find.textContaining('Lovely walk'), findsNothing);

      api.adapter.onGet(
          _page, (server) => server.reply(200, _pageBody('Lovely walk')));
      final reply = api.hold(_page);
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(NTripiRouteLoader), findsOneWidget);

      reply.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Lovely walk'), findsOneWidget);
    });

    testWidgets(
        'Given the reviews on screen, When a pull times out, '
        'Then they stay and the reason shows in a SnackBar', (tester) async {
      final api = RecordingDio();
      await _pump(tester, api, screen);

      _timesOut(api);
      await _pull(tester);

      expect(find.textContaining('Lovely walk'), findsOneWidget);
      expect(find.text(_offline), findsOneWidget);
    });
  });
}
