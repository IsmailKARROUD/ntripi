// test/core/cache/image_cache_eviction_test.dart — clearing covers never costs
// the save or the reload it runs beside.
//
// ImageCacheEviction is best-effort: a cover that cannot be cleared stays stale
// until the next pull, and its error goes no further. Before it, the screens
// called CachedNetworkImage.evictFromCache themselves: an image cache that
// threw put the error into the pull ahead of the reload — which then never
// ran — and turned a saved itinerary form into a reported failure.
//
// The real cache cannot be reached under test (no temporary directory, no
// database), so each case clears through an evictor it can watch or break.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/cache/image_cache.dart';

void main() {
  test(
      'Given covers as stored, When evicted, '
      'Then each is cleared once, by its absolute URL', () async {
    final cleared = <String>[];
    await ImageCacheEviction(evictOne: (url) async => cleared.add(url)).evict([
      'https://images.example/itineraries/a.jpg',
      '/uploads/itineraries/b.jpg',
      null,
      'https://images.example/itineraries/a.jpg',
    ]);

    expect(cleared, [
      'https://images.example/itineraries/a.jpg',
      '$kApiBaseUrl/uploads/itineraries/b.jpg',
    ]);
  });

  test(
      'Given an image cache that throws, When covers are evicted, '
      'Then it completes, and every cover is still tried', () async {
    final tried = <String>[];
    final eviction = ImageCacheEviction(evictOne: (url) async {
      tried.add(url);
      throw const FileSystemException('the image cache could not be opened');
    });

    await expectLater(
      eviction.evict([
        'https://images.example/itineraries/a.jpg',
        'https://images.example/itineraries/b.jpg',
      ]),
      completes,
    );
    expect(tried, hasLength(2));
  });

  test('Given nothing to clear, When evicted, Then nothing is tried', () async {
    final tried = <String>[];
    await ImageCacheEviction(evictOne: (url) async => tried.add(url))
        .evict([null, null]);
    expect(tried, isEmpty);
  });
}
