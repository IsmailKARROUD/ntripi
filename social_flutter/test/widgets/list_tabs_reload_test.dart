// test/widgets/list_tabs_reload_test.dart — pulling a list keeps the list.
//
// Saved, Discover, Account status and the Itineraries tab, end to end on the
// real repositories: a pull that fails keeps the rows on screen and says why in
// a SnackBar, Retry from an error view loads the list in its place, and the
// Itineraries tab clears its covers from the image cache before reloading —
// through ImageCacheEviction, whose failure can never stop the reload.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/cache/image_cache.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/feed/data/feed_repository.dart';
import 'package:ntripi/features/feed/presentation/feed_screen.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_list_screen.dart';
import 'package:ntripi/features/itineraries/presentation/saved_itineraries_screen.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/presentation/account_status_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';

import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _offline =
    'No internet connection. Please check your network and try again.';

/// One list screen, the GET its list comes from, and that GET's body for a row
/// titled [title].
class _Tab {
  const _Tab(this.name, this.screen, this.path, this.body);

  final String name;
  final Widget screen;
  final Pattern path;
  final Object Function(String title) body;
}

final _tabs = [
  _Tab('Saved', const SavedItinerariesScreen(), kSavedItinerariesEndpoint,
      (title) => [summaryJson(title: title)]),
  _Tab('Discover', const FeedScreen(), RegExp(r'^/itineraries/feed\?'),
      (title) => [sharedRowJson(summaryJson(title: title))]),
  _Tab(
    'Account status',
    const AccountStatusScreen(),
    kViolationsEndpoint,
    (title) => {
      'violations': [
        {
          'id': 'v-1',
          'action': 'hide',
          'target_type': 'itinerary',
          'target_id': kTripId,
          'item_title': title,
          'created_at': '2026-10-20T10:00:00Z',
          'active': true,
          'appealable': false,
        },
      ],
    },
  ),
];

Future<void> _pump(
  WidgetTester tester,
  RecordingDio api,
  Widget screen, {
  ImageCacheEviction? eviction,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({});

  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(api.dio)),
      feedRepositoryProvider.overrideWithValue(FeedRepository(api.dio)),
      profileRepositoryProvider.overrideWithValue(ProfileRepository(api.dio)),
      // The image cache cannot answer in a test; the eviction's own contract is
      // image_cache_eviction_test.dart.
      imageCacheEvictionProvider.overrideWithValue(
          eviction ?? ImageCacheEviction(evictOne: (_) async {})),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Past the indicator's arming distance: a quarter of the list's height.
Future<void> _pull(WidgetTester tester) async {
  await tester.fling(
      find.byType(RefreshIndicator).first, const Offset(0, 1000), 1000);
  await tester.pumpAndSettle();
}

void _timesOut(RecordingDio api, Pattern path) => api.adapter.onGet(
      path,
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: '/list'),
          type: DioExceptionType.receiveTimeout,
        ),
      ),
    );

void main() {
  for (final tab in _tabs) {
    group(tab.name, () {
      testWidgets(
          'Given the list on screen, When a pull fails, '
          'Then the rows stay and the reason shows in a SnackBar',
          (tester) async {
        final api = RecordingDio();
        api.adapter.onGet(tab.path, (server) => server.reply(200, tab.body('Before')));
        await _pump(tester, api, tab.screen);
        expect(find.text('Before'), findsWidgets);

        _timesOut(api, tab.path);
        await _pull(tester);

        expect(find.text('Before'), findsWidgets);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(_offline), findsOneWidget);
      });

      testWidgets(
          'Given the list on screen, When a pull is answered, '
          'Then the answer replaces it', (tester) async {
        final api = RecordingDio();
        api.adapter.onGet(tab.path, (server) => server.reply(200, tab.body('Before')));
        await _pump(tester, api, tab.screen);

        api.adapter.onGet(tab.path, (server) => server.reply(200, tab.body('After')));
        await _pull(tester);

        expect(find.text('After'), findsWidgets);
        expect(find.text('Before'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets(
          'Given the list failed to load, When Retry is tapped, '
          'Then the list loads in place of the error', (tester) async {
        final api = RecordingDio();
        api.adapter.onGet(tab.path,
            (server) => server.reply(500, {'detail': 'Internal Server Error'}));
        await _pump(tester, api, tab.screen);
        expect(find.text('Before'), findsNothing);

        api.adapter.onGet(tab.path, (server) => server.reply(200, tab.body('Before')));
        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Before'), findsWidgets);
        expect(find.byType(SnackBar), findsNothing);
      });
    });
  }

  group('Itineraries', () {
    const cover = '/uploads/itineraries/$kTripId.jpg';

    // A card's CachedNetworkImage cannot fetch in a test; that is noise, not
    // what is under test.
    setUp(() {
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
    });

    void lists(RecordingDio api, String title) {
      api.adapter.onGet(kMyItinerariesEndpoint,
          (server) => server.reply(200, [summaryJson(title: title, coverUrl: cover)]));
      api.adapter.onGet(kSharedWithMeEndpoint, (server) => server.reply(200, []));
    }

    int listGets(RecordingDio api) => api.sent
        .where((o) =>
            o.path == kMyItinerariesEndpoint || o.path == kSharedWithMeEndpoint)
        .length;

    testWidgets(
        'Given rows with covers, When pulled, '
        'Then the covers are cleared first and both lists reload',
        (tester) async {
      final api = RecordingDio();
      lists(api, 'Before');
      // Each URL cleared, with how many list GETs had gone out by then.
      final cleared = <({String url, int listGets})>[];
      await _pump(
        tester,
        api,
        const ItineraryListScreen(),
        eviction: ImageCacheEviction(
            evictOne: (url) async =>
                cleared.add((url: url, listGets: listGets(api)))),
      );
      final loads = listGets(api);

      lists(api, 'After');
      await _pull(tester);

      // Stored relative, cleared absolute — and before either reload went out.
      expect(cleared, [(url: '$kApiBaseUrl$cover', listGets: loads)]);
      expect(listGets(api), loads + 2);
      expect(find.text('After'), findsOneWidget);
    });

    testWidgets(
        'Given covers the image cache cannot clear, When pulled, '
        'Then the lists still reload', (tester) async {
      final api = RecordingDio();
      lists(api, 'Before');
      await _pump(
        tester,
        api,
        const ItineraryListScreen(),
        eviction: ImageCacheEviction(
            evictOne: (_) async => throw const FileSystemException(
                'the image cache could not be opened')),
      );

      lists(api, 'After');
      await _pull(tester);

      expect(find.text('After'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Given rows on screen, When a pull fails, '
        'Then the rows stay and the reason shows in a SnackBar',
        (tester) async {
      final api = RecordingDio();
      lists(api, 'Before');
      await _pump(tester, api, const ItineraryListScreen());

      _timesOut(api, kMyItinerariesEndpoint);
      await _pull(tester);

      expect(find.text('Before'), findsOneWidget);
      expect(find.text(_offline), findsOneWidget);
    });
  });
}
