// test/providers/reload_keeps_content_test.dart — a reload never blanks what a
// screen already shows.
//
// Every notifier's refresh() goes through ReloadKeepsContent. With content on
// screen, it stays there for the whole reload: the state keeps its value and is
// never loading, so AsyncValue.when() never swaps in the loader. Then:
//   an answer replaces it in place;
//   a timeout or a 5xx leaves it, and refresh() hands the failure back for the
//   screen that started it to report;
//   a refusal (a 404 here) replaces it with the error.
// One case per notifier, against the real repositories on a mocked Dio, and a
// held reply for "while it reloads".

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/providers/locale_provider.dart';
import 'package:ntripi/core/providers/reload_keeps_content.dart';
import 'package:ntripi/features/feed/data/feed_repository.dart';
import 'package:ntripi/features/feed/domain/feed_item.dart';
import 'package:ntripi/features/feed/providers/feed_providers.dart';
import 'package:ntripi/features/follows/data/follow_repository.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/ratings_page.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:ntripi/features/notifications/data/notification_repository.dart';
import 'package:ntripi/features/notifications/domain/app_notification.dart';
import 'package:ntripi/features/notifications/providers/notification_provider.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/domain/violation.dart';
import 'package:ntripi/features/profile/domain/visited_location.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/profile/providers/user_locations_provider.dart';
import 'package:ntripi/shared/models/follow.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/held_claim.dart';
import '../support/recording_dio.dart';
import '../support/trip_json.dart';

const _them = 'them-1';

/// English, without the secure-storage read the real one starts with.
class _English extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

/// The real repositories, all on [api]; online; no automatic retry, as the
/// app's root scope sets it.
ProviderContainer _container(RecordingDio api) => ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        localeProvider.overrideWith(_English.new),
        itineraryRepositoryProvider
            .overrideWithValue(ItineraryRepository(api.dio)),
        followRepositoryProvider.overrideWithValue(FollowRepository(api.dio)),
        profileRepositoryProvider.overrideWithValue(ProfileRepository(api.dio)),
        feedRepositoryProvider.overrideWithValue(FeedRepository(api.dio)),
        notificationRepositoryProvider
            .overrideWithValue(NotificationRepository(api.dio)),
        editLockProvider.overrideWith2(HeldClaim.new),
      ],
    );

/// A few turns of the event loop: enough for a refresh() to reach its held
/// request.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Bodies — each shape carries 'Before' or 'After' somewhere a label can read.
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _summaries(String title) => [summaryJson(title: title)];

List<Map<String, dynamic>> _feedRows(String title) =>
    [sharedRowJson(summaryJson(title: title))];

Map<String, dynamic> _ratingsPage(String title) => {
      // The page has no title; its count tells Before (1) from After (2).
      'rating_avg': 4.0,
      'rating_count': title == 'Before' ? 1 : 2,
      'distribution': {'five': 0, 'four': 1, 'three': 0, 'two': 0, 'one': 0},
      'ratings': <Map<String, dynamic>>[],
    };

Map<String, dynamic> _user(String id, String username) => {
      'id': id,
      'username': username,
      'display_name': null,
      'avatar_url': null,
      'cover_image_url': null,
      'is_private': false,
      'followers_count': 0,
      'following_count': 0,
      'is_following': false,
      'follow_is_pending': false,
      'follows_you': false,
      'created_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> _violations(String title) => {
      'violations': [
        {
          'id': 'v-1',
          'action': 'hide',
          'target_type': 'itinerary',
          'target_id': kTripId,
          'item_title': title,
          'created_at': '2026-10-20T10:00:00Z',
          'active': true,
          'appealable': true,
          'appeal_status': null,
          'cooldown_until': null,
        },
      ],
    };

Map<String, dynamic> _locations(String title) => {
      'locations': [
        {
          'lat': 43.3,
          'lng': 5.4,
          'place_name': title,
          'place_type': null,
          'itinerary_id': kTripId,
          'stop_id': 'stop-1',
        },
      ],
    };

List<Map<String, dynamic>> _requests(String username) => [
      {
        'follow_id': 'follow-1',
        'follower_id': 'u-1',
        'username': username,
        'display_name': null,
        'avatar_url': null,
        'requested_at': '2026-10-20T10:00:00Z',
      },
    ];

Map<String, dynamic> _person(String username) => {
      'id': 'id-$username',
      'username': username,
      'display_name': null,
      'avatar_url': null,
      'is_private': false,
    };

Map<String, dynamic> _notification(String id) => {
      'id': id,
      'type': 'new_follower',
      'subtype': null,
      'created_at': '2026-10-20T10:00:00Z',
      'read': false,
      'actor_id': 'u-1',
      'actor_username': 'someone',
      'actor_display_name': null,
      'actor_avatar_url': null,
      'entity_type': 'user',
      'entity_id': 'u-1',
    };

Map<String, dynamic> _notifications(List<String> ids) => {
      'notifications': [for (final id in ids) _notification(id)],
      'unread_count': ids.length,
      'latest_at': '2026-10-20T10:00:00Z',
    };

// ---------------------------------------------------------------------------
// One case per notifier
// ---------------------------------------------------------------------------

class _Case {
  const _Case(
    this.name, {
    required this.path,
    required this.body,
    required this.watch,
    required this.load,
    required this.read,
    required this.refresh,
    required this.label,
  });

  final String name;

  /// The GET the screen loaded, and the reload sends.
  final Pattern path;

  /// What that GET answers, for 'Before' (the loaded copy) or 'After'.
  final Object Function(String which) body;

  /// Keeps the provider alive (one of them is autoDispose).
  final void Function(ProviderContainer c) watch;
  final Future<Object?> Function(ProviderContainer c) load;
  final AsyncValue<Object?> Function(ProviderContainer c) read;
  final Future<ReloadFailure?> Function(ProviderContainer c) refresh;

  /// 'Before' or 'After', read from the state's value.
  final String Function(Object? value) label;
}

String _title(Object? v) => (v as List<Itinerary>).single.title;
String _rowTitle(Object? v) => (v as List<FeedItem>).single.itinerary.title;

final _cases = <_Case>[
  _Case(
    'SavedItinerariesNotifier',
    path: kSavedItinerariesEndpoint,
    body: _summaries,
    watch: (c) => c.listen(savedItinerariesProvider, (_, _) {}),
    load: (c) => c.read(savedItinerariesProvider.future),
    read: (c) => c.read(savedItinerariesProvider),
    refresh: (c) => c.read(savedItinerariesProvider.notifier).refresh(),
    label: _title,
  ),
  _Case(
    'MyItinerariesNotifier',
    path: kMyItinerariesEndpoint,
    body: _summaries,
    watch: (c) => c.listen(myItinerariesProvider, (_, _) {}),
    load: (c) => c.read(myItinerariesProvider.future),
    read: (c) => c.read(myItinerariesProvider),
    refresh: (c) => c.read(myItinerariesProvider.notifier).refresh(),
    label: _title,
  ),
  _Case(
    'SharedWithMeNotifier',
    path: kSharedWithMeEndpoint,
    body: _feedRows,
    watch: (c) => c.listen(sharedWithMeProvider, (_, _) {}),
    load: (c) => c.read(sharedWithMeProvider.future),
    read: (c) => c.read(sharedWithMeProvider),
    refresh: (c) => c.read(sharedWithMeProvider.notifier).refresh(),
    label: _rowTitle,
  ),
  _Case(
    'ItineraryDetailNotifier',
    path: itineraryEndpoint(kTripId),
    body: (which) => tripJson(title: which),
    watch: (c) => c.listen(itineraryDetailProvider(kTripId), (_, _) {}),
    load: (c) => c.read(itineraryDetailProvider(kTripId).future),
    read: (c) => c.read(itineraryDetailProvider(kTripId)),
    refresh: (c) => c.read(itineraryDetailProvider(kTripId).notifier).refresh(),
    label: (v) => (v as Itinerary).title,
  ),
  _Case(
    'UserItinerariesNotifier',
    path: userItinerariesEndpoint(_them),
    body: _summaries,
    watch: (c) => c.listen(userItinerariesProvider(_them), (_, _) {}),
    load: (c) => c.read(userItinerariesProvider(_them).future),
    read: (c) => c.read(userItinerariesProvider(_them)),
    refresh: (c) => c.read(userItinerariesProvider(_them).notifier).refresh(),
    label: _title,
  ),
  _Case(
    'RatingsPageNotifier',
    path: itineraryRatingsEndpoint(kTripId),
    body: _ratingsPage,
    watch: (c) => c.listen(ratingsPageProvider(kTripId), (_, _) {}),
    load: (c) => c.read(ratingsPageProvider(kTripId).future),
    read: (c) => c.read(ratingsPageProvider(kTripId)),
    refresh: (c) => c.read(ratingsPageProvider(kTripId).notifier).refresh(),
    label: (v) => (v as RatingsPage).ratingCount == 1 ? 'Before' : 'After',
  ),
  _Case(
    'MyProfileNotifier',
    path: kMyProfileEndpoint,
    body: (which) => _user('me-1', which),
    watch: (c) => c.listen(myProfileProvider, (_, _) {}),
    load: (c) => c.read(myProfileProvider.future),
    read: (c) => c.read(myProfileProvider),
    refresh: (c) => c.read(myProfileProvider.notifier).refresh(),
    label: (v) => (v as User).username,
  ),
  _Case(
    'UserProfileNotifier',
    path: userProfileEndpoint(_them),
    body: (which) => _user(_them, which),
    watch: (c) => c.listen(userProfileProvider(_them), (_, _) {}),
    load: (c) => c.read(userProfileProvider(_them).future),
    read: (c) => c.read(userProfileProvider(_them)),
    refresh: (c) => c.read(userProfileProvider(_them).notifier).refresh(),
    label: (v) => (v as User).username,
  ),
  _Case(
    'MyViolationsNotifier',
    path: kViolationsEndpoint,
    body: _violations,
    watch: (c) => c.listen(myViolationsProvider, (_, _) {}),
    load: (c) => c.read(myViolationsProvider.future),
    read: (c) => c.read(myViolationsProvider),
    refresh: (c) => c.read(myViolationsProvider.notifier).refresh(),
    label: (v) => (v as List<Violation>).single.itemTitle!,
  ),
  _Case(
    'UserLocationsNotifier',
    path: userLocationsEndpoint(_them),
    body: _locations,
    watch: (c) => c.listen(userLocationsProvider(_them), (_, _) {}),
    load: (c) => c.read(userLocationsProvider(_them).future),
    read: (c) => c.read(userLocationsProvider(_them)),
    refresh: (c) => c.read(userLocationsProvider(_them).notifier).refresh(),
    label: (v) => (v as List<VisitedLocation>).single.placeName!,
  ),
  _Case(
    'FeedNotifier',
    // The feed's query rides in its path.
    path: RegExp(r'^/itineraries/feed\?'),
    body: _feedRows,
    watch: (c) => c.listen(feedProvider, (_, _) {}),
    load: (c) => c.read(feedProvider.future),
    read: (c) => c.read(feedProvider),
    refresh: (c) => c.read(feedProvider.notifier).refresh(),
    label: _rowTitle,
  ),
  _Case(
    'FollowRequestsNotifier',
    path: kFollowRequestsEndpoint,
    body: _requests,
    watch: (c) => c.listen(followRequestsProvider, (_, _) {}),
    load: (c) => c.read(followRequestsProvider.future),
    read: (c) => c.read(followRequestsProvider),
    refresh: (c) => c.read(followRequestsProvider.notifier).refresh(),
    label: (v) => (v as List<FollowRequestItem>).single.username,
  ),
  _Case(
    'FollowersNotifier (FollowListNotifier)',
    path: followersEndpoint(_them),
    body: (which) => [_person(which)],
    watch: (c) => c.listen(followersProvider(_them), (_, _) {}),
    load: (c) => c.read(followersProvider(_them).future),
    read: (c) => c.read(followersProvider(_them)),
    refresh: (c) => c.read(followersProvider(_them).notifier).refresh(),
    label: (v) => (v as List<FollowerListItem>).single.username,
  ),
  _Case(
    'FollowingNotifier (FollowListNotifier)',
    path: followingEndpoint(_them),
    body: (which) => [_person(which)],
    watch: (c) => c.listen(followingProvider(_them), (_, _) {}),
    load: (c) => c.read(followingProvider(_them).future),
    read: (c) => c.read(followingProvider(_them)),
    refresh: (c) => c.read(followingProvider(_them).notifier).refresh(),
    label: (v) => (v as List<FollowerListItem>).single.username,
  ),
  _Case(
    'NotificationsNotifier',
    path: kNotificationsEndpoint,
    body: (which) => _notifications([which]),
    watch: (c) => c.listen(notificationsProvider, (_, _) {}),
    load: (c) => c.read(notificationsProvider.future),
    read: (c) => c.read(notificationsProvider),
    refresh: (c) => c.read(notificationsProvider.notifier).refresh(),
    label: (v) => (v as List<AppNotification>).single.id,
  ),
];

DioException _timeout(RequestOptions sent) =>
    DioException(requestOptions: sent, type: DioExceptionType.receiveTimeout);

void main() {
  for (final c in _cases) {
    group(c.name, () {
      late RecordingDio api;
      late ProviderContainer container;

      void answer(int status, Object body) =>
          api.adapter.onGet(c.path, (server) => server.reply(status, body));

      setUp(() async {
        api = RecordingDio();
        container = _container(api);
        addTearDown(container.dispose);
        c.watch(container);
        answer(200, c.body('Before'));
        await c.load(container);
        expect(c.label(c.read(container).value), 'Before');
      });

      test('the content stays while it reloads, then the answer replaces it',
          () async {
        answer(200, c.body('After'));
        final reply = api.hold(c.path);
        final sentBefore = api.sent.length;

        final reload = c.refresh(container);
        await _settle();

        // The reload's request is out and held: this is the screen meanwhile.
        expect(api.sent, hasLength(sentBefore + 1));
        final during = c.read(container);
        expect(during.isLoading, isFalse, reason: 'when() would draw the loader');
        expect(during.hasError, isFalse);
        expect(c.label(during.value), 'Before');

        reply.complete();
        expect(await reload, isNull);
        final after = c.read(container);
        expect((after.isLoading, after.hasError), (false, false));
        expect(c.label(after.value), 'After');
      });

      test('a timeout keeps the content and hands the failure back', () async {
        api.adapter.onGet(c.path,
            (server) => server.throws(408, _timeout(RequestOptions())));

        final failure = await c.refresh(container);

        expect(
          failure?.error,
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.receiveTimeout),
        );
        final after = c.read(container);
        expect((after.isLoading, after.hasError), (false, false));
        expect(c.label(after.value), 'Before');
      });

      test('a server error keeps the content and hands the failure back',
          () async {
        answer(500, {'detail': 'Internal Server Error'});

        final failure = await c.refresh(container);

        expect(
          failure?.error,
          isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 500),
        );
        final after = c.read(container);
        expect((after.isLoading, after.hasError), (false, false));
        expect(c.label(after.value), 'Before');
      });

      test('a 404 replaces the content with the error', () async {
        answer(404, {'detail': 'Not found.', 'code': 'not_found'});

        // The error view says it; nothing is left for a SnackBar.
        expect(await c.refresh(container), isNull);

        final after = c.read(container);
        expect(after.hasError, isTrue);
        expect((after.error as DioException).response?.statusCode, 404);
      });
    });
  }

  group('the rules around the content', () {
    late RecordingDio api;
    late ProviderContainer container;

    setUp(() {
      api = RecordingDio();
      container = _container(api);
      addTearDown(container.dispose);
    });

    test('with nothing on screen, Retry shows the loader, then the error',
        () async {
      container.listen(savedItinerariesProvider, (_, _) {});
      api.adapter.onGet(kSavedItinerariesEndpoint,
          (server) => server.reply(500, {'detail': 'Internal Server Error'}));
      await expectLater(container.read(savedItinerariesProvider.future),
          throwsA(isA<DioException>()));

      final reply = api.hold(kSavedItinerariesEndpoint);
      final retry = container.read(savedItinerariesProvider.notifier).refresh();
      await _settle();
      expect(container.read(savedItinerariesProvider).isLoading, isTrue);

      reply.complete();
      // The error view is the report: nothing comes back for a SnackBar.
      expect(await retry, isNull);
      final after = container.read(savedItinerariesProvider);
      expect((after.isLoading, after.hasError), (false, true));
    });

    test('a save answered while the reload was in flight stands', () async {
      container.listen(myItinerariesProvider, (_, _) {});
      api.adapter.onGet(kMyItinerariesEndpoint,
          (server) => server.reply(200, _summaries('Before')));
      await container.read(myItinerariesProvider.future);

      api.adapter.onGet(kMyItinerariesEndpoint,
          (server) => server.reply(200, _summaries('After')));
      final reply = api.hold(kMyItinerariesEndpoint);
      final reload = container.read(myItinerariesProvider.notifier).refresh();
      await _settle();
      // A trip save's answer replaces its row: newer than a GET sent before it.
      container
          .read(myItinerariesProvider.notifier)
          .replaceRow(Itinerary.fromJson(summaryJson(title: 'Saved')));
      reply.complete();

      expect(await reload, isNull);
      expect(_title(container.read(myItinerariesProvider).value), 'Saved');
    });

    test('a notification dismissed during the reload stays dismissed',
        () async {
      container.listen(notificationsProvider, (_, _) {});
      api.adapter.onGet(kNotificationsEndpoint,
          (server) => server.reply(200, _notifications(['n1', 'n2'])));
      await container.read(notificationsProvider.future);

      final reply = api.hold(kNotificationsEndpoint);
      final notifier = container.read(notificationsProvider.notifier);
      final reload = notifier.refresh();
      await _settle();
      // Its DELETE waits out the undo window, so the server still lists it.
      expect(notifier.dismiss('n1'), isTrue);
      reply.complete();

      expect(await reload, isNull);
      expect(
        container.read(notificationsProvider).value!.map((n) => n.id),
        ['n2'],
      );
    });

    test('a follow-list page requested before a reload landed is dropped',
        () async {
      final path = followersEndpoint(_them);
      void page(int offset, List<Map<String, dynamic>> rows) =>
          api.adapter.onGet(path, (server) => server.reply(200, rows),
              queryParameters: {'limit': kFollowListPageSize, 'offset': offset});

      container.listen(followersProvider(_them), (_, _) {});
      page(0, [for (var i = 0; i < kFollowListPageSize; i++) _person('p$i')]);
      await container.read(followersProvider(_them).future);
      final notifier = container.read(followersProvider(_them).notifier);
      expect(notifier.hasMore, isTrue);

      // The next page goes out first and is held...
      page(kFollowListPageSize, [_person('old-next')]);
      final nextPage = api.hold(path);
      final more = notifier.loadMore();
      await _settle();

      // ...while a pull's reload lands with a shorter list.
      page(0, [_person('fresh')]);
      expect(await notifier.refresh(), isNull);

      nextPage.complete();
      await more;

      final rows = container.read(followersProvider(_them)).value!;
      expect(rows.map((r) => r.username), ['fresh']);
      expect(notifier.hasMore, isFalse);
    });

    test(
        'a save that took the view answers no trip; a GET that then times out '
        'keeps the trip, and the save reports it', () async {
      container.listen(itineraryDetailProvider(kTripId), (_, _) {});
      api.adapter.onGet(itineraryEndpoint(kTripId),
          (server) => server.reply(200, tripJson(title: 'Before')));
      await container.read(itineraryDetailProvider(kTripId).future);

      api.adapter.onPatch(
        itineraryEndpoint(kTripId),
        (server) => server.reply(200, tripAnswer(null)),
        data: Matchers.any,
        queryParameters: {'return': 'itinerary'},
      );
      api.adapter.onGet(itineraryEndpoint(kTripId),
          (server) => server.throws(408, _timeout(RequestOptions())));

      await expectLater(
        container
            .read(itineraryDetailProvider(kTripId).notifier)
            .updateHeader({'description': 'Shorter.'}),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.receiveTimeout)),
      );
      final trip = container.read(itineraryDetailProvider(kTripId));
      expect((trip.isLoading, trip.hasError), (false, false));
      expect(trip.value!.title, 'Before');
    });

    test('a refused profile save throws and leaves the profile as it was',
        () async {
      container.listen(myProfileProvider, (_, _) {});
      api.adapter.onGet(
          kMyProfileEndpoint, (server) => server.reply(200, _user('me-1', 'before')));
      await container.read(myProfileProvider.future);

      api.adapter.onPatch(
        kMyProfileEndpoint,
        (server) => server.reply(422, {
          'detail': 'Rejected.',
          'code': 'text_moderation_rejected',
        }),
        data: Matchers.any,
      );

      await expectLater(
        container.read(myProfileProvider.notifier).updateProfile(bio: 'x'),
        throwsA(isA<DioException>()),
      );
      final profile = container.read(myProfileProvider);
      expect((profile.isLoading, profile.hasError), (false, false));
      expect(profile.value!.username, 'before');

      // And a save that lands is the state.
      api.adapter.onPatch(kMyProfileEndpoint,
          (server) => server.reply(200, _user('me-1', 'after')),
          data: Matchers.any);
      await container.read(myProfileProvider.notifier).updateProfile(bio: 'y');
      expect(container.read(myProfileProvider).value!.username, 'after');
    });
  });
}
