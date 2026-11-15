// test/models/order_by_distance_golden_test.dart — the same answers on every
// device. Thirty fixed trips (order_by_distance_days.dart), every choice,
// held to the answers saved once in order_by_distance_golden.dart:
//
//   flutter test test/models/order_by_distance_golden_test.dart
//   flutter test --platform chrome test/models/order_by_distance_golden_test.dart
//
// and on a phone, integration_test/order_by_distance_device_test.dart. A
// platform that rounds a distance differently, a generator that draws other
// numbers, or a 64-bit typed list on the web, fails here.

import 'package:flutter_test/flutter_test.dart';

import '../support/order_by_distance_days.dart';
import 'order_by_distance_golden.dart';

void main() {
  test(
      'Given the 30 fixed trips, When every choice is worked out, Then every '
      'answer is the one saved in the golden file', () async {
    final lines = await orderGoldenOf(orderDays());
    expect(lines.keys, orderGolden.keys);
    for (final MapEntry(:key, :value) in orderGolden.entries) {
      expect(lines[key], value, reason: key);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
