// test/widgets/user_profile_screen_test.dart
//
// Widget tests for the Editorial other-user profile (UserProfileScreen).
// Covers the four follow states and the private-account lock state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/presentation/profile_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

// ignore_for_file: invalid_use_of_internal_member

// ── Fixtures ──────────────────────────────────────────────────────────────

const _userId = 'other-1';

User _makeUser({
  bool isPrivate = false,
  bool isFollowing = false,
  bool followIsPending = false,
}) =>
    User(
      id: _userId,
      username: 'aminad',
      displayName: 'Amina Diallo',
      bio: 'Storyteller from Dakar',
      avatarUrl: null,
      isPrivate: isPrivate,
      followersCount: 247,
      followingCount: 38,
      isFollowing: isFollowing,
      followIsPending: followIsPending,
      createdAt: DateTime(2024),
    );

final _testItinerary = Itinerary(
  id: 'it-1',
  userId: _userId,
  title: 'Dakar to Saint-Louis',
  totalDurationMin: 260,
  totalCost: 210,
  currency: 'EUR',
  visibility: ItineraryVisibility.public,
  createdAt: DateTime(2025),
  updatedAt: DateTime(2025),
  stopsCount: 9,
);

// ── Fake notifiers ────────────────────────────────────────────────────────

class _FakeUserProfile extends UserProfileNotifier {
  _FakeUserProfile(this._user);
  final User _user;
  @override
  Future<User> build(String userId) async => _user;
}

class _FakeUserProfileLoading extends UserProfileNotifier {
  @override
  Future<User> build(String userId) => Completer<User>().future;
}

class _FakeUserProfileError extends UserProfileNotifier {
  @override
  Future<User> build(String userId) async =>
      throw Exception('Not found');
}

class _FakeUserItineraries extends UserItinerariesNotifier {
  _FakeUserItineraries(this._items);
  final List<Itinerary> _items;
  @override
  Future<List<Itinerary>> build(String userId) async => _items;
}

// ── Widget builder ────────────────────────────────────────────────────────

List<Override> _overrides({
  User? user,
  List<Itinerary>? itineraries,
  UserProfileNotifier Function()? profileNotifier,
}) {
  final u = user ?? _makeUser();
  return [
    userProfileProvider.overrideWith(
        profileNotifier ?? () => _FakeUserProfile(u)),
    userItinerariesProvider
        .overrideWith(() => _FakeUserItineraries(itineraries ?? [_testItinerary])),
  ];
}

Widget _buildScreen({
  User? user,
  List<Itinerary>? itineraries,
  UserProfileNotifier Function()? profileNotifier,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: _overrides(
        user: user, itineraries: itineraries, profileNotifier: profileNotifier),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ProfileScreen(userId: _userId),
    ),
  );
}

Widget _buildRouterScreen({
  required GoRouter router,
  User? user,
  List<Itinerary>? itineraries,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: _overrides(user: user, itineraries: itineraries),
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  // Same tile-error suppression as my_profile_screen_test — OSM requests
  // fail with HTTP 400 in test mode and would otherwise fail every test.
  setUp(() {
    final orig = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.library == 'image resource service') return;
      orig?.call(details);
    };
    addTearDown(() => FlutterError.onError = orig);
  });

  group('UserProfileScreen', () {
    // ── Profile data ─────────────────────────────────────────────────────

    group('profile data', () {
      testWidgets(
          'Given public user, When screen builds, '
          'Then shows display name and handle', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.text('Amina Diallo'), findsOneWidget);
        expect(find.text('@aminad'), findsOneWidget);
      });

      testWidgets(
          'Given public user, When screen builds, '
          'Then shows followers and following counts', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
      });

      testWidgets(
          'Given public user, When screen builds, '
          'Then shows back button', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        expect(find.byTooltip('Back'), findsOneWidget);
      });

      testWidgets(
          'Given public user with itineraries, When screen builds, '
          'Then shows ITINERARIES section label', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(itineraries: [_testItinerary]));
        await tester.pump();

        expect(find.text('ITINERARIES'), findsOneWidget);
      });
    });

    // ── Private account — locked content ─────────────────────────────────

    group('private account', () {
      testWidgets(
          'Given private user not following, When screen builds, '
          'Then shows "This account is private" message', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(user: _makeUser(isPrivate: true)));
        await tester.pump();

        expect(find.text('This account is private'), findsOneWidget);
      });

      testWidgets(
          'Given private user with pending follow request, '
          'When screen builds, Then shows "Request sent"', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
            user: _makeUser(isPrivate: true, followIsPending: true)));
        await tester.pump();

        expect(find.text('Request sent'), findsOneWidget);
      });

      testWidgets(
          'Given private account not following, When screen builds, '
          'Then ITINERARIES section is not shown', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(user: _makeUser(isPrivate: true)));
        await tester.pump();

        expect(find.text('ITINERARIES'), findsNothing);
      });

      testWidgets(
          'Given private user that current user follows, '
          'When screen builds, Then shows itineraries section', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
            user: _makeUser(isPrivate: true, isFollowing: true)));
        await tester.pump();

        expect(find.text('ITINERARIES'), findsOneWidget);
      });
    });

    // ── Navigation — profileBaseRoute ─────────────────────────────────────

    group('navigation — profileBaseRoute', () {
      // Shared router factory used by both navigation tests below.
      GoRouter makeRouter({required String base}) => GoRouter(
            initialLocation: '$base/$_userId',
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, __) => const SizedBox.shrink(),
                routes: [
                  GoRoute(
                    path: 'profile/:userId',
                    builder: (_, s) => ProfileScreen(
                      userId: s.pathParameters['userId']!,
                      profileBaseRoute: '/search/profile',
                    ),
                    routes: [
                      GoRoute(
                        path: 'followers',
                        builder: (_, s) => Scaffold(
                          body: Text(
                              'followers:${s.pathParameters['userId']}'),
                        ),
                      ),
                      GoRoute(
                        path: 'following',
                        builder: (_, s) => Scaffold(
                          body: Text(
                              'following:${s.pathParameters['userId']}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: '/profile/:userId',
                builder: (_, s) => ProfileScreen(
                  userId: s.pathParameters['userId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'followers',
                    builder: (_, s) => Scaffold(
                      body:
                          Text('followers:${s.pathParameters['userId']}'),
                    ),
                  ),
                  GoRoute(
                    path: 'following',
                    builder: (_, s) => Scaffold(
                      body:
                          Text('following:${s.pathParameters['userId']}'),
                    ),
                  ),
                ],
              ),
            ],
          );

      testWidgets(
          'Given profileBaseRoute=/search/profile, '
          'When Followers tapped, '
          'Then navigates to /search/profile/{userId}/followers',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildRouterScreen(
            router: makeRouter(base: '/search/profile')));
        await tester.pump();

        await tester.tap(find.text('Followers'));
        await tester.pumpAndSettle();

        expect(find.text('followers:$_userId'), findsOneWidget);
      });

      testWidgets(
          'Given profileBaseRoute=/search/profile, '
          'When Following tapped, '
          'Then navigates to /search/profile/{userId}/following',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildRouterScreen(
            router: makeRouter(base: '/search/profile')));
        await tester.pump();

        await tester.tap(find.text('Following'));
        await tester.pumpAndSettle();

        expect(find.text('following:$_userId'), findsOneWidget);
      });

      testWidgets(
          'Given default profileBaseRoute, '
          'When Followers tapped, '
          'Then navigates to /profile/{userId}/followers',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildRouterScreen(router: makeRouter(base: '/profile')));
        await tester.pump();

        await tester.tap(find.text('Followers'));
        await tester.pumpAndSettle();

        expect(find.text('followers:$_userId'), findsOneWidget);
      });
    });

    // ── Loading / error ───────────────────────────────────────────────────

    group('loading and error states', () {
      testWidgets(
          'Given profile is loading, When screen builds, '
          'Then shows NTripiCompassLoader', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(profileNotifier: _FakeUserProfileLoading.new));
        await tester.pump();

        expect(find.byType(NTripiCompassLoader), findsOneWidget);
      });

      testWidgets(
          'Given profile fetch fails, When screen builds, '
          'Then shows Retry button', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(profileNotifier: _FakeUserProfileError.new));
        await tester.pump();

        expect(find.text('Retry'), findsOneWidget);
      });
    });

    // ── Layout coverage introduced by the unified ProfileScreen ──────────

    group('other-user layout (merged screen)', () {
      testWidgets(
          'Given other-user profile, When section header renders, '
          'Then "LATEST TRIP" and "See all" are not shown', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(itineraries: [_testItinerary]));
        await tester.pump();

        // These are self-only conditionals in _SectionHeader.
        expect(find.text('LATEST TRIP'), findsNothing);
        expect(find.text('See all'), findsNothing);
      });

      testWidgets(
          'Given multiple itineraries, When screen builds, '
          'Then all cards are in the tree (not capped at 1 like self preview)',
          (tester) async {
        // Tall viewport so the sliver builds both cards.
        tester.view.physicalSize = const Size(1080, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final second = Itinerary(
          id: 'it-2',
          userId: _userId,
          title: 'Mbour beach loop',
          totalDurationMin: 120,
          totalCost: 90,
          currency: 'EUR',
          visibility: ItineraryVisibility.public,
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
          stopsCount: 3,
        );
        await tester.pumpWidget(
            _buildScreen(itineraries: [_testItinerary, second]));
        await tester.pump();
        await tester.pump(); // settle itineraries AsyncNotifier

        // Both ItinerarySummaryCard widgets must exist in the tree —
        // proves childCount = itineraries.length for other-user mode.
        expect(find.byType(ItinerarySummaryCard), findsNWidgets(2));
      });

      testWidgets(
          'Given other-user public profile, When screen builds, '
          'Then follow action row is visible',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();

        // The decorative message button icon proves FollowActionRow rendered.
        expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
      });

      testWidgets(
          'Given private account viewer does not follow, '
          'When screen builds, Then follow action row is hidden',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(user: _makeUser(isPrivate: true)));
        await tester.pump();

        expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
      });

      testWidgets(
          'Given user has no bio, When screen builds, '
          'Then bio is not rendered', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final noBio = User(
          id: _userId,
          username: 'aminad',
          displayName: 'Amina Diallo',
          bio: null,
          avatarUrl: null,
          isPrivate: false,
          followersCount: 247,
          followingCount: 38,
          createdAt: DateTime(2024),
        );
        await tester.pumpWidget(_buildScreen(user: noBio));
        await tester.pump();

        expect(find.textContaining('Storyteller'), findsNothing);
      });
    });
  });
}
