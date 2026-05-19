// test/providers/search_provider_test.dart — Riverpod unit tests for
// SearchResultsNotifier and searchQueryProvider.
//
// Strategy:
//   - Subclass SearchRepository and override searchUsers to capture calls.
//   - Override searchRepositoryProvider in a ProviderContainer.
//   - Drive the search query via searchQueryProvider.notifier.state = '...'.
//   - Debouncing lives in the UI layer (Timer), so the provider fires immediately
//     here — no artificial delays needed.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/search/data/search_repository.dart';
import 'package:social_flutter/features/search/providers/search_provider.dart';
import 'package:social_flutter/shared/models/user.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeSearchRepo extends SearchRepository {
  _FakeSearchRepo() : super(Dio());

  final List<String> searchCalls = [];
  List<User> usersToReturn = [];

  @override
  Future<List<User>> searchUsers(String query,
      {int limit = 20, int offset = 0}) async {
    searchCalls.add(query);
    return usersToReturn;
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

User _makeUser({String id = 'u1', String username = 'alice'}) => User(
      id: id,
      username: username,
      email: null,
      displayName: null,
      bio: null,
      avatarUrl: null,
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      isFollowing: false,
      followIsPending: false,
      createdAt: DateTime.utc(2026, 1, 1),
      passportCountries: null,
      residentCountry: null,
      languages: null,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeSearchRepo fakeRepo;
  late ProviderContainer container;

  setUp(() {
    fakeRepo = _FakeSearchRepo();
    container = ProviderContainer(overrides: [
      searchRepositoryProvider.overrideWithValue(fakeRepo),
    ]);
  });

  tearDown(() => container.dispose());

  group('SearchResultsNotifier — empty / whitespace queries', () {
    test('Given empty query (initial state), returns empty list without calling repo',
        () async {
      final results = await container.read(searchResultsProvider.future);

      expect(results, isEmpty);
      expect(fakeRepo.searchCalls, isEmpty);
    });

    test('Given whitespace-only query, returns empty list without calling repo',
        () async {
      container.read(searchQueryProvider.notifier).state = '   ';
      final results = await container.read(searchResultsProvider.future);

      expect(results, isEmpty);
      expect(fakeRepo.searchCalls, isEmpty);
    });
  });

  group('SearchResultsNotifier — non-empty query', () {
    test('Given non-empty query, calls repo.searchUsers with that query',
        () async {
      container.read(searchQueryProvider.notifier).state = 'alice';
      await container.read(searchResultsProvider.future);

      expect(fakeRepo.searchCalls, ['alice']);
    });

    test('Given query with surrounding spaces, calls repo with trimmed query',
        () async {
      container.read(searchQueryProvider.notifier).state = '  alice  ';
      await container.read(searchResultsProvider.future);

      expect(fakeRepo.searchCalls, ['alice']);
    });

    test('Given repo returns users, provider exposes them', () async {
      fakeRepo.usersToReturn = [_makeUser(username: 'alice')];
      container.read(searchQueryProvider.notifier).state = 'alice';

      final results = await container.read(searchResultsProvider.future);

      expect(results, hasLength(1));
      expect(results.single.username, 'alice');
    });

    test('Given repo returns empty list, provider exposes empty list', () async {
      fakeRepo.usersToReturn = [];
      container.read(searchQueryProvider.notifier).state = 'unknown_xyz';

      final results = await container.read(searchResultsProvider.future);

      expect(results, isEmpty);
    });
  });

  group('SearchResultsNotifier — query changes', () {
    test('When query changes from empty to non-empty, repo is called', () async {
      // Initial state — empty query, no call.
      await container.read(searchResultsProvider.future);
      expect(fakeRepo.searchCalls, isEmpty);

      // Update the query.
      container.read(searchQueryProvider.notifier).state = 'bob';
      await container.read(searchResultsProvider.future);

      expect(fakeRepo.searchCalls, ['bob']);
    });

    test('When query changes from non-empty to empty, repo is not called again',
        () async {
      container.read(searchQueryProvider.notifier).state = 'alice';
      await container.read(searchResultsProvider.future);
      expect(fakeRepo.searchCalls, hasLength(1));

      // Clear the query.
      container.read(searchQueryProvider.notifier).state = '';
      final results = await container.read(searchResultsProvider.future);

      expect(results, isEmpty);
      // Still only one call total — clearing doesn't trigger another search.
      expect(fakeRepo.searchCalls, hasLength(1));
    });

    test('When query changes between two non-empty values, repo is called twice',
        () async {
      container.read(searchQueryProvider.notifier).state = 'alice';
      await container.read(searchResultsProvider.future);

      container.read(searchQueryProvider.notifier).state = 'bob';
      await container.read(searchResultsProvider.future);

      expect(fakeRepo.searchCalls, ['alice', 'bob']);
    });
  });
}
