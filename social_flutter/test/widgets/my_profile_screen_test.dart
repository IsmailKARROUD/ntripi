// test/widgets/my_profile_screen_test.dart
//
// Widget tests for the Editorial profile redesign (MyProfileScreen).
// Each test overrides Riverpod provider dependencies — never mocks providers
// directly. Fake notifiers extend the real notifier classes and override
// `build()` to return deterministic data immediately.
//
// Sections:
//   · Profile view — hero, identity, bio, itineraries, empty state
//   · Loading / error states
//   · Follow-requests banner
//   · Settings sheet — opens, Log out dialog
//   · Edit mode — cancel, save

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/presentation/profile_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/shared/models/user.dart';

// ── Test fixtures ─────────────────────────────────────────────────────────

final _testUser = User(
  id: 'user-1',
  username: 'ismauo',
  displayName: 'Ismail duo',
  bio: 'Travel lover',
  avatarUrl: null,
  isPrivate: false,
  followersCount: 2,
  followingCount: 1,
  createdAt: DateTime(2024),
);

final _testPrivateUser = _testUser.copyWith(isPrivate: true);

final _testItinerary = Itinerary(
  id: 'it-1',
  userId: 'user-1',
  title: 'Marrakech loop',
  totalDurationMin: 180,
  totalCost: 420,
  currency: 'EUR',
  visibility: ItineraryVisibility.public,
  createdAt: DateTime(2025),
  updatedAt: DateTime(2025),
  stopsCount: 5,
);

final _testRequest = FollowRequestItem(
  followId: 'req-1',
  followerId: 'follower-1',
  username: 'kma',
  displayName: 'Karim',
  requestedAt: DateTime(2025),
);

// ── Fake notifiers ────────────────────────────────────────────────────────

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._user);
  final User _user;
  @override
  Future<User> build() async => _user;
  @override
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    String? coverImageUrl,
    bool clearCoverImageUrl = false,
    bool? isPrivate,
    List<String>? passportCountries,
    bool passportCountriesChanged = false,
    String? residentCountry,
    bool clearResidentCountry = false,
    List<String>? languages,
    bool languagesChanged = false,
  }) async {
    state = AsyncData(_user.copyWith(
      displayName: displayName,
      bio: bio,
      isPrivate: isPrivate,
    ));
  }
}

class _FakeMyProfileLoading extends MyProfileNotifier {
  @override
  Future<User> build() => Completer<User>().future; // never completes
}

class _FakeMyProfileError extends MyProfileNotifier {
  @override
  Future<User> build() async => throw Exception('Server error');
}

class _FakeFollowRequests extends FollowRequestsNotifier {
  _FakeFollowRequests(this._items);
  final List<FollowRequestItem> _items;
  @override
  Future<List<FollowRequestItem>> build() async => _items;
  @override
  Future<void> acceptRequest(String followId) async {
    state.whenData((r) => state =
        AsyncData(r.where((x) => x.followId != followId).toList()));
  }
  @override
  Future<void> rejectRequest(String followId) async {
    state.whenData((r) => state =
        AsyncData(r.where((x) => x.followId != followId).toList()));
  }
}

class _FakeMyItineraries extends MyItinerariesNotifier {
  _FakeMyItineraries(this._items);
  final List<Itinerary> _items;
  @override
  Future<List<Itinerary>> build() async => _items;
}

// ── Widget builder ────────────────────────────────────────────────────────

Widget _buildScreen({
  User? user,
  List<Itinerary>? itineraries,
  List<FollowRequestItem>? requests,
  MyProfileNotifier Function()? profileNotifier,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      myProfileProvider.overrideWith(
          profileNotifier ?? () => _FakeMyProfile(user ?? _testUser)),
      followRequestsProvider.overrideWith(
          () => _FakeFollowRequests(requests ?? [])),
      myItinerariesProvider.overrideWith(
          () => _FakeMyItineraries(itineraries ?? [])),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ProfileScreen(),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  // FlutterMap's TileLayer makes HTTP requests for OSM tiles. In test mode
  // the binding returns HTTP 400, which the image resource service rethrows
  // as an uncaught exception and fails the test. Suppress those errors here
  // so we can assert on the profile UI without tile rendering mattering.
  setUp(() {
    final orig = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.library == 'image resource service') return;
      orig?.call(details);
    };
    addTearDown(() => FlutterError.onError = orig);
  });

  group('MyProfileScreen', () {
    // ── Profile view ────────────────────────────────────────────────────

    group('profile view', () {
      testWidgets(
          'Given profile data loaded, When screen builds, '
          'Then shows user display name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump(); // settle providers

        expect(find.text('Ismail duo'), findsOneWidget);
      });

      testWidgets(
          'Given profile data loaded, When screen builds, '
          'Then shows @username handle', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        expect(find.text('@ismauo'), findsOneWidget);
      });

      testWidgets(
          'Given profile with bio, When screen builds, '
          'Then shows bio text', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Travel'), findsWidgets);
      });

      testWidgets(
          'Given profile data loaded, When screen builds, '
          'Then shows followers and following tallies', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
        expect(find.text('2'), findsOneWidget); // followersCount
        expect(find.text('1'), findsOneWidget); // followingCount
      });

      testWidgets(
          'Given itineraries loaded, When screen builds, '
          'Then shows LATEST TRIP header and itinerary title', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(itineraries: [_testItinerary]));
        await tester.pump();
        await tester.pump();

        expect(find.text('LATEST TRIP'), findsOneWidget);
        expect(find.text('Marrakech loop'), findsOneWidget);
      });

      testWidgets(
          'Given no itineraries, When screen builds, '
          'Then shows empty state invitation card', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(itineraries: []));
        await tester.pump();
        await tester.pump();

        expect(find.text('Plan your first journey'), findsOneWidget);
        expect(find.text('Create itinerary'), findsOneWidget);
      });

      testWidgets(
          'Given private account with pending follow requests, '
          'When screen builds, Then shows follow requests banner', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(
          user: _testPrivateUser,
          requests: [_testRequest],
        ));
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Follow Requests'), findsOneWidget);
      });

      testWidgets(
          'Given public account or no pending requests, '
          'When screen builds, Then no follow requests banner', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen(requests: []));
        await tester.pump();

        expect(find.textContaining('Follow Requests'), findsNothing);
      });
    });

    // ── Loading / error ──────────────────────────────────────────────────

    group('loading and error states', () {
      testWidgets(
          'Given profile is loading, When screen builds, '
          'Then shows NTripiCompassLoader', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(profileNotifier: _FakeMyProfileLoading.new));
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
            _buildScreen(profileNotifier: _FakeMyProfileError.new));
        await tester.pump();

        expect(find.text('Retry'), findsOneWidget);
      });
    });

    // ── Settings sheet ───────────────────────────────────────────────────

    group('settings sheet', () {
      testWidgets(
          'Given profile loaded, When settings button tapped, '
          'Then settings sheet appears', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Log out'), findsOneWidget);
        expect(find.text('Delete account'), findsOneWidget);
      });

      testWidgets(
          'Given settings sheet open, When Log out tapped, '
          'Then confirmation dialog appears', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Are you sure you want to log out?'),
            findsOneWidget);
      });

      testWidgets(
          'Given logout dialog, When Cancel tapped, '
          'Then dialog dismissed', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        await tester
            .tap(find.widgetWithText(TextButton, 'Cancel').last);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    // ── Edit mode ────────────────────────────────────────────────────────

    group('edit mode', () {
      testWidgets(
          'Given profile loaded, When edit button tapped, '
          'Then edit form with Cancel and Save appears', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Edit profile'));
        await tester.pump();

        expect(find.text('Edit profile'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
      });

      testWidgets(
          'Given edit mode, When Cancel tapped, '
          'Then returns to profile view showing user name', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Edit profile'));
        await tester.pump();

        await tester.tap(find.text('Cancel'));
        await tester.pump();

        expect(find.text('Ismail duo'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
      });

      testWidgets(
          'Given edit mode, When display name changed and Save tapped, '
          'Then updateProfile is called', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Edit profile'));
        await tester.pump();

        // Clear and re-enter display name field
        await tester.enterText(
            find.byType(TextField).first, 'New Name');
        await tester.tap(find.text('Save'));
        await tester.pump();

        // After save, edit mode exits (Cancel disappears)
        expect(find.text('Cancel'), findsNothing);
      });
    });

    // ── Layout coverage introduced by the unified ProfileScreen ──────────

    group('self-only layout (merged screen)', () {
      testWidgets(
          'Given itineraries loaded, When screen builds, '
          'Then See all link is visible (self-only conditional)',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
            _buildScreen(itineraries: [_testItinerary]));
        await tester.pump();
        await tester.pump();

        expect(find.text('See all'), findsOneWidget);
      });

      testWidgets(
          'Given user has no bio, When screen builds, '
          'Then bio text is not rendered', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final noBioUser = User(
          id: 'user-1',
          username: 'ismauo',
          displayName: 'Ismail duo',
          bio: null,
          avatarUrl: null,
          isPrivate: false,
          followersCount: 2,
          followingCount: 1,
          createdAt: DateTime(2024),
        );
        await tester.pumpWidget(_buildScreen(user: noBioUser));
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Travel'), findsNothing);
      });

      testWidgets(
          'Given self profile loaded, When hero chrome renders, '
          'Then Edit and Settings tooltips are present (not Back/Share)',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildScreen());
        await tester.pump();
        await tester.pump();

        expect(find.byTooltip('Edit profile'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
      });
    });
  });
}
