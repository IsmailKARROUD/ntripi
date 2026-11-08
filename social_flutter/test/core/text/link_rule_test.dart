// The app's link detector answers like the server's for every shared sample
// (social_api/test/test_link_rule.py reads the same list).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/text/link_rule.dart';

void main() {
  final samples = (jsonDecode(
    File('test/support/link_rule_samples.json').readAsStringSync(),
  ) as Map<String, dynamic>)['samples'] as List;

  for (final c in samples.cast<Map<String, dynamic>>()) {
    test('Given ${c['why']}, When read, Then it finds ${c['match'] ?? 'no link'}',
        () {
      expect(findLink(c['text'] as String), c['match'],
          reason: c['text'] as String);
    });
  }
}
