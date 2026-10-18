// test/widgets/notification_destinations_exit_test.dart
//
// Every screen a notification can open has a way out — in every state, and
// even as the ONLY route on its navigator.
//
// A tap is routed so that something sits beneath its screen
// (test/core/push/tap_routing_test.dart), but these screens do not lean on
// that: a web refresh, or any future way in, can still open one alone.
// Regression: the other-user profile's back arrow was a bare maybePop() —
// nothing to pop, so nothing happened — its error state had no way back at
// all, and its "account unavailable" page hid Go back exactly when it was
// alone. The trip's error state had no way back either, and an AppBar draws no
// back button on a route that cannot pop. Every exit now goes through popOr,
// to the page that would have been underneath.
//
// The first test fails until a new notification destination has a case here.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/router/app_router.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/presentation/follow_requests_screen.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/my_rating.dart';
import 'package:ntripi/features/itineraries/domain/ratings_page.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:ntripi/features/notifications/domain/app_notification.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/domain/violation.dart';
import 'package:ntripi/features/profile/domain/visited_location.dart';
import 'package:ntripi/features/profile/presentation/account_status_screen.dart';
import 'package:ntripi/features/profile/presentation/profile_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

/// The route template of every screen a notification can open — each has a
/// case below.
const _covered = {
  '/profile/:userId',
  '/follow-requests',
  '/settings/account-status',
  '/itineraries/:id',
  '/itineraries/:id/ratings',
};

// ── Fixtures ──────────────────────────────────────────────────────────────

final _me = User(
  id: 'me-1',
  username: 'ismauo',
  isPrivate: false,
  followersCount: 0,
  followingCount: 0,
  createdAt: DateTime.utc(2024),
);

final _them = User(
  id: 'u1',
  username: 'aminad',
  displayName: 'Amina Diallo',
  isPrivate: false,
  followersCount: 3,
  followingCount: 1,
  createdAt: DateTime.utc(2024),
);

final _trip = Itinerary(
  id: 'it1',
  userId: 'u1',
  title: 'Dakar to Saint-Louis',
  totalDurationMin: 0,
  totalCost: 0.0,
  currency: 'EUR',
  visibility: ItineraryVisibility.public,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

DioException _status(int code) {
  final request = RequestOptions(path: '/');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: code,
      data: const {'detail': 'x'},
    ),
  );
}

// ── Fakes ─────────────────────────────────────────────────────────────────
// They answer the screens' own reads. Anything else falls through to a Dio
// with no server behind it and fails, as it would offline.

class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo({this.profile}) : super(Dio());

  /// What GET /users/{id} answers: the user, or the error to throw.
  final Object? profile;

  @override
  Future<User> getMyProfile() async => _me;

  @override
  Future<User> getUserProfile(String userId) async {
    final answer = profile ?? _them;
    if (answer is User) return answer;
    throw answer;
  }

  @override
  Future<List<VisitedLocation>> getUserLocations(String userId) async =>
      const [];

  @override
  Future<List<Violation>> getViolations() async => const [];
}

class _FakeItineraryRepo extends ItineraryRepository {
  _FakeItineraryRepo({this.itinerary}) : super(Dio());

  /// What GET /itineraries/{id} answers: the trip, or the error to throw.
  final Object? itinerary;

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final answer = itinerary ?? _trip;
    if (answer is Itinerary) return answer;
    throw answer;
  }

  @override
  Future<List<Itinerary>> getUserItineraries(
    String userId, {
    bool forceRefresh = false,
  }) async =>
      const [];

  @override
  Future<RatingsPage> getRatingsPage(
    String itineraryId, {
    bool forceRefresh = false,
  }) async =>
      const RatingsPage(
        ratingAvg: null,
        ratingCount: 0,
        distribution:
            RatingDistribution(five: 0, four: 0, three: 0, two: 0, one: 0),
        ratings: [],
      );

  @override
  Future<MyRating?> getMyRating(String itineraryId) async => null;
}

class _FakeFollowRepo extends FollowRepository {
  _FakeFollowRepo() : super(Dio());

  @override
  Future<List<FollowRequestItem>> getFollowRequests({
    bool forceRefresh = false,
  }) async =>
      const [];
}

// ── Harness ───────────────────────────────────────────────────────────────

/// Pumps the screen at [location] as the ONLY route on its navigator, beside a
/// stub at [fallback] — the page its exit should land on.
Future<void> _pumpAlone(
  WidgetTester tester, {
  required String path,
  required String location,
  required GoRouterWidgetBuilder screen,
  required String fallback,
  ProfileRepository? profiles,
  ItineraryRepository? itineraries,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      // First, so /profile/me is never read as /profile/:userId.
      GoRoute(path: fallback, builder: (_, _) => const Text('fallback page')),
      GoRoute(path: path, builder: screen),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    // Riverpod 3 auto-retries thrown Exceptions; an error state must stay put.
    retry: (_, _) => null,
    overrides: [
      profileRepositoryProvider
          .overrideWithValue(profiles ?? _FakeProfileRepo()),
      itineraryRepositoryProvider
          .overrideWithValue(itineraries ?? _FakeItineraryRepo()),
      followRepositoryProvider.overrideWithValue(_FakeFollowRepo()),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await tester.pump();
  await tester.pump();

  // Nothing beneath it, so whatever the exit does, a pop alone cannot work.
  expect(router.canPop(), isFalse);
}

Future<void> _leaveThrough(WidgetTester tester, Finder exit) async {
  expect(exit, findsOneWidget);
  await tester.tap(exit);
  await tester.pumpAndSettle();
  expect(find.text('fallback page'), findsOneWidget);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // OSM tiles answer HTTP 400 under test; same suppression as the profile
    // screen's own tests.
    final orig = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.library == 'image resource service') return;
      orig?.call(details);
    };
    addTearDown(() => FlutterError.onError = orig);
  });

  testWidgets(
      'Given every notification type, '
      'When its destination is matched in the app router, '
      'Then that screen has an exit case in this file', (tester) async {
    for (final type in NotificationType.values) {
      final route =
          notificationRoute(type: type, actorId: 'u1', entityId: 'it1');
      if (route == null) continue;
      final template =
          appRouter.configuration.findMatch(Uri.parse(route)).fullPath;
      expect(_covered, contains(template),
          reason: '$type opens $template — add an exit case for it here');
    }
  });

  group("Someone else's profile", () {
    Future<void> pumpProfile(WidgetTester tester, {Object? answer}) =>
        _pumpAlone(
          tester,
          path: '/profile/:userId',
          location: '/profile/u1',
          screen: (_, state) =>
              ProfileScreen(userId: state.pathParameters['userId']!),
          fallback: '/profile/me',
          profiles: _FakeProfileRepo(profile: answer),
        );

    testWidgets(
        'Given the profile loaded, When Back is tapped, '
        'Then it lands on your own profile', (tester) async {
      await pumpProfile(tester);
      await _leaveThrough(tester, find.byTooltip('Back'));
    });

    testWidgets(
        'Given the profile failed to load, When Go back is tapped, '
        'Then it lands on your own profile', (tester) async {
      await pumpProfile(tester, answer: _status(500));
      expect(find.text('Retry'), findsOneWidget);
      await _leaveThrough(tester, find.text('Go back'));
    });

    testWidgets(
        'Given the account is gone, When Go back is tapped, '
        'Then it lands on your own profile', (tester) async {
      await pumpProfile(tester, answer: _status(404));
      await _leaveThrough(tester, find.text('Go back'));
    });
  });

  group('A trip', () {
    Future<void> pumpTrip(WidgetTester tester, {Object? answer}) => _pumpAlone(
          tester,
          path: '/itineraries/:id',
          location: '/itineraries/it1',
          screen: (_, state) =>
              ItineraryDetailScreen(itineraryId: state.pathParameters['id']!),
          fallback: '/itineraries',
          itineraries: _FakeItineraryRepo(itinerary: answer),
        );

    testWidgets(
        'Given the trip loaded, When Back is tapped, '
        'Then it lands on the Itineraries tab', (tester) async {
      await pumpTrip(tester);
      await _leaveThrough(tester, find.byIcon(Icons.arrow_back_rounded));
    });

    testWidgets(
        'Given the trip is gone, When Go back is tapped, '
        'Then it lands on the Itineraries tab', (tester) async {
      await pumpTrip(tester, answer: _status(404));
      expect(find.text('Retry'), findsOneWidget);
      await _leaveThrough(tester, find.text('Go back'));
    });
  });

  testWidgets(
      "Given a trip's ratings, When Back is tapped, "
      'Then it lands on the trip', (tester) async {
    await _pumpAlone(
      tester,
      path: '/itineraries/:id/ratings',
      location: '/itineraries/it1/ratings',
      screen: (_, state) =>
          RatingsHubScreen(itineraryId: state.pathParameters['id']!),
      fallback: '/itineraries/:id',
    );
    await _leaveThrough(tester, find.byTooltip('Back'));
  });

  testWidgets(
      'Given follow requests, When Back is tapped, '
      'Then it lands on your own profile', (tester) async {
    await _pumpAlone(
      tester,
      path: '/follow-requests',
      location: '/follow-requests',
      screen: (_, _) => const FollowRequestsScreen(),
      fallback: '/profile/me',
    );
    await _leaveThrough(tester, find.byTooltip('Back'));
  });

  testWidgets(
      'Given account status, When Back is tapped, '
      'Then it lands on your own profile', (tester) async {
    await _pumpAlone(
      tester,
      path: '/settings/account-status',
      location: '/settings/account-status',
      screen: (_, _) => const AccountStatusScreen(),
      fallback: '/profile/me',
    );
    await _leaveThrough(tester, find.byTooltip('Back'));
  });
}
