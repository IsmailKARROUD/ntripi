// test/speed/order_by_distance_speed_test.dart — how long Order by distance
// takes, kept apart from the normal tests: every choice for a 12-track trip
// (12 movable tracks at most, the exact search's limit) and for 60 tracks,
// the largest size checked — the app sets no limit. Skipped unless asked for:
//
//   flutter test --dart-define=ORDER_SPEED=true test/speed
//   flutter test --platform chrome --dart-define=ORDER_SPEED=true test/speed
//
// Each budget is about ten times what that runner measured on the
// development Mac (2026-11-15), so only a real slowdown fails. The browser
// runner compiles without release optimisation; release builds and phones:
// docs/features/order-by-distance.md and the device test.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

import '../support/order_by_distance_fixtures.dart';

const _run = bool.fromEnvironment('ORDER_SPEED');

/// Milliseconds to work out every choice for [tracks].
Future<int> _allChoices(List<Track> tracks) async {
  final watch = Stopwatch()..start();
  final c = await orderByDistanceChoices(TripArrangement.of(tracks), const []);
  watch.stop();
  expect(c!.hasSuggestion, isTrue);
  return watch.elapsedMilliseconds;
}

void main() {
  group('Order by distance speed', () {
    test('Given 12 tracks, When every choice is worked out, Then it stays '
        'within its budget', () async {
      final ms = await _allChoices(scatteredTracks(12, seed: 1201));
      // ignore: avoid_print
      print('12 tracks, every choice: $ms ms');
      // Measured 40–43 ms on the VM, 135 ms in the browser runner.
      expect(ms, lessThan(kIsWeb ? 1500 : 450));
    });

    test('Given 60 tracks, When every choice is worked out, Then it stays '
        'within its budget', () async {
      final ms = await _allChoices(scatteredTracks(60, seed: 6001));
      // ignore: avoid_print
      print('60 tracks, every choice: $ms ms');
      // Measured 1.57–1.66 s on the VM, 50 s in the browser runner.
      expect(ms, lessThan(kIsWeb ? 500000 : 16000));
    }, timeout: const Timeout(Duration(minutes: 10)));
  },
      skip: _run
          ? false
          : 'Speed checks run on their own: --dart-define=ORDER_SPEED=true');
}
