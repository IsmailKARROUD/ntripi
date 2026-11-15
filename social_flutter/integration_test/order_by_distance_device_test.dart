// integration_test/order_by_distance_device_test.dart — Order by distance on a
// phone: the 30 golden days must come out exactly as on the test VM and in
// the browser, the generator must draw the same numbers, and the timings are
// printed for the phone's own budget. A profile build gives the real times:
//
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/order_by_distance_device_test.dart -d <phone>
//
// (`flutter test integration_test/order_by_distance_device_test.dart -d
// <phone>` checks the answers too, in a debug build, whose times mean little.)

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

import '../test/models/order_by_distance_golden.dart';
import '../test/support/order_by_distance_days.dart';
import '../test/support/order_by_distance_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Given the 30 fixed trips, When worked out on this phone, Then every '
      'answer is the golden one', (tester) async {
    final lines = await orderGoldenOf(orderDays());
    expect(lines.keys, orderGolden.keys);
    for (final MapEntry(:key, :value) in orderGolden.entries) {
      expect(lines[key], value, reason: key);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(
      'Given seed 12345, When xorshift32 draws on this phone, Then the pinned '
      'numbers', (tester) async {
    final rng = XorShift32(kOrderSeed);
    expect([for (var i = 0; i < 5; i++) rng.next()],
        [3336926330, 1697253807, 2816511904, 1955480042, 718842323]);
  });

  testWidgets(
      'Given 12 and 60 tracks, When every choice is worked out on this phone, '
      'Then the times are printed', (tester) async {
    for (final (count, seed) in [(12, 1201), (60, 6001)]) {
      final watch = Stopwatch()..start();
      final c = await orderByDistanceChoices(
          TripArrangement.of(scatteredTracks(count, seed: seed)), const []);
      watch.stop();
      expect(c!.hasSuggestion, isTrue);
      // ignore: avoid_print
      print('$count tracks, every choice: ${watch.elapsedMilliseconds} ms');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
