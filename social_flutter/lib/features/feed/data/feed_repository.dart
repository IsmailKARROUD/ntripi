// features/feed/data/feed_repository.dart — public discovery feed API calls.
//
// Mirrors ItineraryRepository: takes the shared Dio singleton and reuses
// forceRefreshOptions() for pull-to-refresh / retry.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';

/// Page size requested per feed fetch. The notifier uses this to decide whether
/// more pages remain (a short page means we hit the end).
const kFeedPageSize = 20;

class FeedRepository {
  final Dio _dio;

  const FeedRepository(this._dio);

  Future<List<FeedItem>> getFeed({
    required String sort,
    int limit = kFeedPageSize,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      feedEndpoint(sort: sort, limit: limit, offset: offset),
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(FeedItem.fromJson)
        .toList();
  }
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(dio);
});
