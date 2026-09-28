// core/api/cache_key.dart — the HTTP cache's key: the account plus the URL.
//
// Keyed on the URL alone, the disk cache served one account's responses to the
// next person to sign in on the device: `/users/me` (email, date of birth),
// `/itineraries/me` and `/notifications` are the same URL for everybody, and the
// offline branch of dio_cache_interceptor always falls back to the cache. Logout
// cleans the store, but a session can also end on the interceptor's forced paths
// (expiry, suspension), which never reach it — so the key itself separates them.

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

/// RequestOptions.extra key under which AuthInterceptor records the JWT `sub`
/// of the session a request belongs to (expired tokens included).
const kCacheSubjectExtra = 'ntripi_cache_subject';

/// The one key builder. DioCacheInterceptor, the per-request refresh options and
/// CacheEvictInterceptor must all use it, or they address different entries.
String ntripiCacheKey(RequestOptions request) {
  final base = CacheOptions.defaultCacheKeyBuilder(request);
  final subject = request.extra[kCacheSubjectExtra];
  return subject is String && subject.isNotEmpty ? '$subject:$base' : base;
}
