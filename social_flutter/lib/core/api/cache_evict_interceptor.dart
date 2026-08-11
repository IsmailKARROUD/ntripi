// core/api/cache_evict_interceptor.dart — drop cached bodies the server has
// just told us we may not see.
//
// [kNeverServeStaleFor] stops the cache layer from ANSWERING a 403/404/410, but
// the entry itself lingers in the store until maxStale (7 days). That matters
// because the offline branch inside dio_cache_interceptor hits the cache
// unconditionally — so a blocked profile would reappear the first time the
// device lost connectivity. Deleting the entry on the way past closes that.
//
// 401 is deliberately NOT evicted even though it is in kNeverServeStaleFor: an
// expired session is temporary and the same data is visible again after
// re-login, so wiping the offline warm cache on a session blip would cost
// offline mode a lot and buy no privacy.

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

/// Status codes whose cached body must be destroyed, not merely bypassed.
const kEvictCacheFor = [403, 404, 410];

class CacheEvictInterceptor extends Interceptor {
  final CacheStore store;

  const CacheEvictInterceptor(this.store);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    // Only GETs are cached, so only GETs can have an entry to remove.
    if (err.requestOptions.method.toUpperCase() == 'GET' &&
        status != null &&
        kEvictCacheFor.contains(status)) {
      try {
        // Must match the keyBuilder DioCacheInterceptor is configured with.
        await store.delete(CacheOptions.defaultCacheKeyBuilder(
          err.requestOptions,
        ));
      } catch (_) {
        // A store failure must not turn a 404 into an unhandled error — the
        // response is already correct, this is only cleanup.
      }
    }
    handler.next(err);
  }
}
