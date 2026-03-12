// features/search/data/search_repository.dart — Search API calls.

import 'package:dio/dio.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/shared/models/user.dart';

class SearchRepository {
  final Dio _dio;

  const SearchRepository(this._dio);

  /// GET /users/search?q=...&limit=20&offset=0
  Future<List<User>> searchUsers(String query, {int limit = 20, int offset = 0}) async {
    final response = await _dio.get(
      kSearchUsersEndpoint,
      queryParameters: {
        'q': query,
        'limit': limit,
        'offset': offset,
      },
    );
    final list = response.data as List<dynamic>;
    return list
        .map((item) => User.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
