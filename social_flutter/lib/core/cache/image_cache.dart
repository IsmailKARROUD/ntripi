// core/cache/image_cache.dart — Project-wide image cache.
//
// Single source of truth for how every image in the app is cached on disk.
// Every CachedNetworkImage, CachedNetworkImageProvider, evictFromCache, and
// putFile call routes through NtripiImageCacheManager so cache policy
// (TTL, key namespace, etc.) is changed in one place.

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// How long an image cached on disk stays valid before being re-fetched.
/// Avatars and itinerary cover images are cache-busted server-side with
/// `?v=<ts>` query params, so this TTL is a backstop — most entries are
/// replaced by a new URL long before they expire.
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

/// Deliberately short so a hotlinked Google Open Graph image (a link stop's
/// unfurled preview) is only ever a transient on-device copy — never a
/// long-lived re-host of third-party content.
const Duration kLinkPreviewCacheStalePeriod = Duration(days: 7);

/// Separate namespace + short TTL for unfurled link-preview (og:image) thumbnails.
/// Kept apart from [NtripiImageCacheManager] so these third-party images expire
/// quickly and never mix with our own avatars/covers.
class NtripiLinkPreviewCacheManager extends CacheManager {
  static const _key = 'ntripi_link_preview_cache';
  static final NtripiLinkPreviewCacheManager _instance =
      NtripiLinkPreviewCacheManager._();
  factory NtripiLinkPreviewCacheManager() => _instance;
  NtripiLinkPreviewCacheManager._()
    : super(Config(_key, stalePeriod: kLinkPreviewCacheStalePeriod));
}
