// core/cache/image_cache.dart — Project-wide image cache.
//
// Single source of truth for how every image in the app is cached on disk.
// Every CachedNetworkImage, CachedNetworkImageProvider, evictFromCache, and
// putFile call routes through NtripiImageCacheManager so cache policy
// (TTL, key namespace, etc.) is changed in one place.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_endpoints.dart';

/// How long an image cached on disk stays valid before being re-fetched.
/// Avatars and profile covers are cache-busted server-side with `?v=<ts>`
/// query params, so for them this TTL is a backstop — most entries are replaced
/// by a new URL long before they expire. Itinerary covers are not: see
/// [ImageCacheEviction].
const Duration kImageCacheStalePeriod = Duration(days: 60);

/// Project-wide CacheManager. Use it explicitly with CachedNetworkImage
/// (`cacheManager: NtripiImageCacheManager()`) so every render and eviction
/// touches the same on-disk store under the same key namespace.
class NtripiImageCacheManager extends CacheManager {
  static const _key = 'ntripi_image_cache';
  static final NtripiImageCacheManager _instance = NtripiImageCacheManager._();
  factory NtripiImageCacheManager() => _instance;
  NtripiImageCacheManager._()
    : super(Config(_key, stalePeriod: kImageCacheStalePeriod));
}

/// Drops the cached copies of itinerary covers — on disk and in memory — so the
/// next build fetches them again. A cover keeps its storage key when it is
/// replaced (`itineraries/{id}.jpg`, no `?v=`), so this is the only way a new
/// one shows under the old URL: after a save that changed it, and before a
/// pull-to-refresh.
///
/// Best-effort: an image cache that cannot be cleared costs a stale cover, never
/// the save or the reload it runs beside — its error must not turn a saved form
/// into a reported failure, or escape into a RefreshIndicator ahead of the
/// reload it was clearing the way for.
class ImageCacheEviction {
  const ImageCacheEviction({this.evictOne = _evictFromCache});

  /// Clears one absolute URL — CachedNetworkImage's own eviction, disk and
  /// memory; a test passes one it can watch or make fail.
  final Future<void> Function(String url) evictOne;

  /// [urls] as stored — relative (`/uploads/…`, filesystem storage) or
  /// absolute; nulls and repeats are skipped.
  Future<void> evict(Iterable<String?> urls) => Future.wait([
        for (final url in {...urls.whereType<String>()})
          _safely(url.startsWith('/') ? '$kApiBaseUrl$url' : url),
      ]);

  Future<void> _safely(String url) async {
    try {
      await evictOne(url);
    } catch (_) {
      // A stale cover until the next pull is the lesser failure.
    }
  }
}

Future<void> _evictFromCache(String url) => CachedNetworkImage.evictFromCache(
      url,
      cacheManager: NtripiImageCacheManager(),
    );

/// [ImageCacheEviction] for the screens that clear covers — a provider so a
/// test can watch what is cleared, and in what order with the reload.
final imageCacheEvictionProvider =
    Provider<ImageCacheEviction>((ref) => const ImageCacheEviction());
