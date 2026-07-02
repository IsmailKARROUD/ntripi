// features/search/providers/search_provider.dart — Search state management.
//
// The search query is stored in a simple Notifier<String>.
// The search results are derived from that query using an AsyncNotifier.
//
// Debouncing (400ms) is implemented in the SearchScreen UI layer using a Timer.
// This means the provider only fires after the user stops typing for 400ms,
// avoiding flooding the API with a request on every keystroke.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/search/data/search_repository.dart';
import 'package:social_flutter/shared/models/user.dart';

/// Provides the SearchRepository singleton.
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(dio);
});

/// The current search query string entered by the user.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

/// Search results, automatically updated when the query changes.
/// Returns an empty list for empty queries (no API call needed).
class SearchResultsNotifier extends AsyncNotifier<List<User>> {
  @override
  Future<List<User>> build() async {
    // Watch the query — whenever it changes, this build() re-runs.
    final query = ref.watch(searchQueryProvider);

    if (query.trim().isEmpty) {
      return [];
    }

    return ref.read(searchRepositoryProvider).searchUsers(query.trim());
  }
}

final searchResultsProvider =
    AsyncNotifierProvider<SearchResultsNotifier, List<User>>(
  () => SearchResultsNotifier(),
);
