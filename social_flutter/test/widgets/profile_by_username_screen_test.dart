// test/widgets/profile_by_username_screen_test.dart
//
// A shared profile link names a handle (/share/u/<name>); every profile route
// in the app takes an account id. ProfileByUsernameScreen resolves one into the
// other and then is the profile screen — your own handle included, which must
// open your own profile rather than a stranger's view of it with a Follow
// button aimed at yourself. A handle that answers 404 (unknown, deleted,
// suspended, or a block either way) gets the one "account unavailable" page.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/domain/violation.dart';
import 'package:ntripi/features/profile/domain/visited_location.dart';
import 'package:ntripi/features/profile/presentation/profile_by_username_screen.dart';
import 'package:ntripi/features/profile/presentation/profile_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

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

class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo(this.byHandle) : super(Dio());

  /// What GET /users/aminad answers — the handle in the link: a user, or the
  /// error to throw. By id it answers as the server would.
  final Object byHandle;

  @override
  Future<User> getMyProfile() async => _me;

  @override
  Future<User> getUserProfile(String identifier) async {
    if (identifier != 'aminad') return identifier == _me.id ? _me : _them;
    final answer = byHandle;
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
  _FakeItineraryRepo() : super(Dio());

  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async =>
      const [];

  @override
  Future<List<Itinerary>> getUserItineraries(
    String userId, {
    bool forceRefresh = false,
  }) async =>
      const [];
}

class _FakeFollowRepo extends FollowRepository {
  _FakeFollowRepo() : super(Dio());

  @override
  Future<List<FollowRequestItem>> getFollowRequests({
    bool forceRefresh = false,
  }) async =>
      const [];
}

/// Pumps the screen for [username] as the only route, beside a stub at
/// /profile/me — where its way out should land.
Future<void> _pump(WidgetTester tester, {required Object byHandle}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/u/aminad',
    routes: [
      GoRoute(
        path: '/profile/me',
        builder: (_, _) => const Text('fallback page'),
      ),
      GoRoute(
        path: '/u/:username',
        builder: (_, state) => ProfileByUsernameScreen(
          username: state.pathParameters['username']!,
        ),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    // Riverpod 3 auto-retries thrown Exceptions; an error state must stay put.
    retry: (_, _) => null,
    overrides: [
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo(byHandle)),
      itineraryRepositoryProvider.overrideWithValue(_FakeItineraryRepo()),
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
      "Given someone else's handle, When it resolves, "
      'Then their profile opens by id', (tester) async {
    await _pump(tester, byHandle: _them);

    final screen = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
    expect(screen.userId, _them.id);
    expect(find.text('Amina Diallo'), findsWidgets);
  });

  testWidgets(
      'Given your own handle, When it resolves, '
      'Then it opens your own profile', (tester) async {
    await _pump(tester, byHandle: _me);

    final screen = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
    expect(screen.isSelf, isTrue);
  });

  testWidgets(
      'Given a handle that answers 404, When Go back is tapped, '
      'Then it lands on your own profile', (tester) async {
    await _pump(tester, byHandle: _status(404));

    // One page for unknown, deleted, suspended and blocked alike — no Retry.
    expect(find.text('Account unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('fallback page'), findsOneWidget);
  });

  testWidgets(
      'Given the lookup failed, When it is shown, '
      'Then it offers Retry and a way back', (tester) async {
    await _pump(tester, byHandle: _status(500));

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });
}
