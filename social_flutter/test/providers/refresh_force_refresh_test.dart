// test/providers/refresh_force_refresh_test.dart — verifies that every
// AsyncNotifier's `.refresh()` opts into `forceRefresh: true` (bypassing the
// dio_cache_interceptor's conditional-GET validator) while initial `build()`
// stays on the default false (so cached responses still satisfy first loads).
//
// Why this matters: pull-to-refresh and error-state Retry both call `.refresh()`.
// The user's intent is "give me fresh data, ignore my local cache." If a
// notifier silently forgets to pass `forceRefresh: true`, swipe-down on an
// unchanged screen 304s and feels broken.
//
// The fake repos here track the `forceRefresh` flag on every call. We assert
// `build()` → false, `.refresh()` → true, end-to-end through Riverpod.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/follows/data/follow_repository.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/models/follow.dart';

// ---------------------------------------------------------------------------
// Fakes — each one records the forceRefresh flag per call so tests can assert
// build() ≠ refresh().
// ---------------------------------------------------------------------------

class _FakeItineraryRepo extends ItineraryRepository {
  _FakeItineraryRepo() : super(Dio());

  final List<bool> getMyItinerariesCalls = [];
  final List<bool> getSharedWithMeCalls = [];
  final List<bool> getItineraryCalls = [];
  final List<bool> getUserItinerariesCalls = [];
  final List<bool> getRatingsPageCalls = [];

  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async {
    getMyItinerariesCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<List<FeedItem>> getSharedWithMe({bool forceRefresh = false}) async {
    getSharedWithMeCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    getItineraryCalls.add(forceRefresh);
    return _makeItinerary();
  }

  @override
  Future<List<Itinerary>> getUserItineraries(
    String userId, {
    bool forceRefresh = false,
  }) async {
    getUserItinerariesCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<RatingsPage> getRatingsPage(
    String itineraryId, {
    bool forceRefresh = false,
  }) async {
    getRatingsPageCalls.add(forceRefresh);
    return const RatingsPage(
      ratingAvg: null,
      ratingCount: 0,
      distribution: RatingDistribution(
        five: 0,
        four: 0,
        three: 0,
        two: 0,
        one: 0,
      ),
      ratings: [],
    );
  }
}

class _FakeFollowRepo implements FollowRepository {
  final List<bool> getFollowRequestsCalls = [];
  final List<bool> getFollowersCalls = [];
  final List<bool> getFollowingCalls = [];

  @override
  Future<List<FollowRequestItem>> getFollowRequests({
    bool forceRefresh = false,
  }) async {
    getFollowRequestsCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<List<FollowerListItem>> getFollowers(
    String userId, {
    bool forceRefresh = false,
  }) async {
    getFollowersCalls.add(forceRefresh);
    return const [];
  }

  @override
  Future<List<FollowerListItem>> getFollowing(
    String userId, {
    bool forceRefresh = false,
  }) async {
    getFollowingCalls.add(forceRefresh);
    return const [];
  }

  // Unused by the tests but required to satisfy the interface contract.
  @override
  Future<Follow> followUser(String userId) => throw UnimplementedError();
  @override
  Future<void> unfollowUser(String userId) => throw UnimplementedError();
  @override
  Future<Follow> acceptFollowRequest(String followId) =>
      throw UnimplementedError();
  @override
  Future<void> rejectFollowRequest(String followId) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _itinId = 'itin-1';
const _userId = 'user-1';

Itinerary _makeItinerary() {
  final ts = DateTime.utc(2026, 5, 11, 10, 22, 56);
  return Itinerary(
    id: _itinId,
    userId: _userId,
    title: 'Trip',
    totalDurationMin: 0,
    totalCost: 0.0,
    currency: 'EUR',
    visibility: ItineraryVisibility.onlyMe,
    createdAt: ts,
    updatedAt: ts,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Itinerary notifiers — .refresh() forces a fresh server fetch', () {
    late _FakeItineraryRepo fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = _FakeItineraryRepo();
      container = ProviderContainer(overrides: [
        itineraryRepositoryProvider.overrideWithValue(fakeRepo),
      ]);
    });

    tearDown(() => container.dispose());

    test(
        'Given MyItinerariesNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(myItinerariesProvider.future);
      await container.read(myItinerariesProvider.notifier).refresh();

      expect(fakeRepo.getMyItinerariesCalls, [false, true]);
    });

    test(
        'Given SharedWithMeNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(sharedWithMeProvider.future);
      await container.read(sharedWithMeProvider.notifier).refresh();

      expect(fakeRepo.getSharedWithMeCalls, [false, true]);
    });

    test(
        'Given ItineraryDetailNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(itineraryDetailProvider(_itinId).future);
      await container
          .read(itineraryDetailProvider(_itinId).notifier)
          .refresh();

      expect(fakeRepo.getItineraryCalls, [false, true]);
    });

    test(
        'Given UserItinerariesNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(userItinerariesProvider(_userId).future);
      await container
          .read(userItinerariesProvider(_userId).notifier)
          .refresh();

      expect(fakeRepo.getUserItinerariesCalls, [false, true]);
    });

    test(
        'Given RatingsPageNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(ratingsPageProvider(_itinId).future);
      await container.read(ratingsPageProvider(_itinId).notifier).refresh();

      expect(fakeRepo.getRatingsPageCalls, [false, true]);
    });
  });

  group('Follow notifiers — .refresh() forces a fresh server fetch', () {
    late _FakeFollowRepo fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = _FakeFollowRepo();
      container = ProviderContainer(overrides: [
        followRepositoryProvider.overrideWithValue(fakeRepo),
      ]);
    });

    tearDown(() => container.dispose());

    test(
        'Given FollowRequestsNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(followRequestsProvider.future);
      await container.read(followRequestsProvider.notifier).refresh();

      expect(fakeRepo.getFollowRequestsCalls, [false, true]);
    });

    test(
        'Given FollowersNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(followersProvider(_userId).future);
      await container.read(followersProvider(_userId).notifier).refresh();

      expect(fakeRepo.getFollowersCalls, [false, true]);
    });

    test(
        'Given FollowingNotifier, '
        'When build() runs then refresh() is called, '
        'Then build uses forceRefresh:false and refresh uses true', () async {
      await container.read(followingProvider(_userId).future);
      await container.read(followingProvider(_userId).notifier).refresh();

      expect(fakeRepo.getFollowingCalls, [false, true]);
    });
  });
}
