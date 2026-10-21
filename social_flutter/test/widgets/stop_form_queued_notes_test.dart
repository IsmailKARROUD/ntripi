// A new stop with notes queued on it saves in one request per write, and none
// after.
//
// The stop form queues notes written before the stop exists, then attaches them
// to the stop its Save created — the id the answer names. Every one of those
// writes answers with the whole trip, which is adopted, so nothing downloads
// the trip again: the stop and two notes are three requests and no GET.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/core/services/location_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/presentation/annotation_screen.dart';
import 'package:ntripi/features/itineraries/presentation/stop_form_screen.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

const _itinId = 'itin-1';

Map<String, dynamic> _stop(String id) => {
      'id': id,
      'itinerary_id': _itinId,
      'track_id': 't1',
      'rank': 'a0',
      'place_name': 'Cove',
      'place_address': null,
      'lat': null,
      'lng': null,
      'map_url': null,
      'place_type': null,
      'duration_min': null,
      'cost': 0.0,
      'is_free': false,
      'notes': null,
      'created_at': '2026-10-21T10:00:05.000000Z',
      'annotations': <Map<String, dynamic>>[],
    };

/// The trip as the GET shows it, before the save (no stop) or after it.
Map<String, dynamic> _trip({bool withStop = false}) => {
      'id': _itinId,
      'user_id': 'user-1',
      'title': 'Coast walk',
      'cover_image_url': null,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-21T09:00:00.000000Z',
      'updated_at': withStop
          ? '2026-10-21T10:00:05.000000Z'
          : '2026-10-21T10:00:00.000000Z',
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': withStop ? 1 : 0,
      'description': null,
      'tracks': [
        if (withStop)
          {
            'id': 't1',
            'itinerary_id': _itinId,
            'rank': 'a0',
            'stops': [_stop('stop-new')],
          },
      ],
      'segments': <Map<String, dynamic>>[],
      'annotations': <Map<String, dynamic>>[],
      'can_edit': true,
    };

/// A claim held by this device, without the network or the heartbeat.
class _HeldClaim extends EditLockNotifier {
  _HeldClaim(super.arg);

  @override
  EditSession build() {
    super.build();
    return const EditSession(token: 'lock-token');
  }
}

class _FakeMyProfile extends MyProfileNotifier {
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

/// No device fix, no permission prompt, no preview map.
class _NoLocation extends LocationService {
  @override
  Future<LocationOutcome> getCurrentLatLng() async => const LocationUnavailable();
}

/// Typing a place name searches Nominatim; nothing here may reach it.
class _NoGeocoding extends GeocodingService {
  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    String? languageCode,
    LatLng? near,
    LatLng? boxSw,
    LatLng? boxNe,
    bool bounded = false,
  }) async =>
      const [];
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a new stop and its two queued notes are three requests, no GET',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final adapter = DioAdapter(dio: dio);
    final sent = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.next(options);
    }));
    adapter
      ..onGet(itineraryEndpoint(_itinId), (server) => server.reply(200, _trip()))
      ..onPost(
        itineraryStopsEndpoint(_itinId),
        (server) => server.reply(
            201, {'itinerary': _trip(withStop: true), 'created_id': 'stop-new'}),
        data: Matchers.any,
        queryParameters: {'return': 'itinerary'},
      )
      ..onPost(
        stopAnnotationsEndpoint(_itinId, 'stop-new'),
        (server) => server.reply(
            201, {'itinerary': _trip(withStop: true), 'created_id': 'note-new'}),
        data: Matchers.any,
        queryParameters: {'return': 'itinerary'},
      );

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: SizedBox())),
      GoRoute(
        path: '/itineraries/:id/stops/new',
        builder: (_, state) =>
            StopFormScreen(itineraryId: state.pathParameters['id']!),
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itineraryRepositoryProvider.overrideWithValue(ItineraryRepository(dio)),
          editLockProvider.overrideWith2(_HeldClaim.new),
          myProfileProvider.overrideWith(_FakeMyProfile.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          locationServiceProvider.overrideWithValue(_NoLocation()),
          geocodingServiceProvider.overrideWithValue(_NoGeocoding()),
        ],
        child: MaterialApp.router(
          theme: buildNtripiTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    router.push('/itineraries/$_itinId/stops/new');
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(StopFormScreen)))!;
    await tester.enterText(find.byType(TextFormField).first, 'Cove');
    await tester.pumpAndSettle();

    // Notes sit among the optional fields, which a new stop starts without.
    final showOptional = find.text(l10n.showOptionalFields);
    await tester.ensureVisible(showOptional);
    await tester.tap(showOptional);
    await tester.pumpAndSettle();

    // Two notes, queued: the stop they belong to does not exist yet.
    for (final note in ['Go early', 'Closed on Mondays']) {
      final addNote = find.descendant(
        of: find.byType(StopFormScreen),
        matching: find.text(l10n.addButton),
      );
      await tester.ensureVisible(addNote);
      await tester.tap(addNote);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
            of: find.byType(AnnotationScreen), matching: find.byType(TextField)),
        note,
      );
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byType(AnnotationScreen), matching: find.text(l10n.addButton)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Go early'), findsOneWidget);
    expect(find.text('Closed on Mondays'), findsOneWidget);

    sent.clear(); // the form's own first load is not the save
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(sent.map((o) => '${o.method} ${o.path}'), [
      'POST ${itineraryStopsEndpoint(_itinId)}',
      'POST ${stopAnnotationsEndpoint(_itinId, 'stop-new')}',
      'POST ${stopAnnotationsEndpoint(_itinId, 'stop-new')}',
    ]);
    // The form closed onto the page beneath it.
    expect(find.byType(StopFormScreen), findsNothing);
  });
}
