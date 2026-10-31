// test/core/cache/absolute_image_url_test.dart — a stored image URL as one an
// image can load: filesystem storage answers a relative path, R2 an absolute
// URL.

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/cache/image_cache.dart';

void main() {
  test('Given a relative path, Then it is served from the API host', () {
    expect(absoluteImageUrl('/uploads/avatars/u1.jpg?v=3'),
        '$kApiBaseUrl/uploads/avatars/u1.jpg?v=3');
  });

  test('Given an absolute URL, Then it is used as it is', () {
    expect(absoluteImageUrl('https://images.ntripi.app/avatars/u1.jpg?v=3'),
        'https://images.ntripi.app/avatars/u1.jpg?v=3');
  });
}
