// test/support/order_by_distance_days.dart — the fixed trips the golden check
// works out on every device: 2 to 40 tracks, of every kind — clustered or
// spread out, transit segments, tracks nothing locates (the first one too),
// Google picks and links, alternatives, stops on one point, round trips, and
// trips across the whole earth. Their answers are in
// test/models/order_by_distance_golden.dart; the VM, the browser and the
// phone must all give exactly those.

import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';

import 'order_by_distance_fixtures.dart';

List<TripDay> orderDays() => [
      randomTrip('two', 1, 2),
      randomTrip('three', 2, 3),
      randomTrip('four-round-trip', 3, 4, roundTrip: true),
      randomTrip('five-clustered', 4, 5, clustered: true),
      randomTrip('six-segments', 5, 6, legPercent: 50),
      randomTrip('seven-first-unlocated', 6, 7, firstUnmeasured: true),
      randomTrip('eight-google-and-links', 7, 8, unmeasuredPercent: 30),
      randomTrip('nine-alternatives', 8, 9, alternativesPercent: 40),
      randomTrip('ten-same-points', 9, 10, samePointPercent: 30),
      randomTrip('eleven', 10, 11),
      randomTrip('twelve-segments', 11, 12, legPercent: 30),
      randomTrip('thirteen', 12, 13),
      randomTrip('fourteen-round-trip', 13, 14, roundTrip: true),
      randomTrip('fifteen-clustered', 14, 15, clustered: true),
      randomTrip('sixteen-unlocated', 15, 16,
          unmeasuredPercent: 20, firstUnmeasured: true),
      randomTrip('eighteen-segments-unlocated', 16, 18,
          legPercent: 25, unmeasuredPercent: 15),
      randomTrip('twenty', 17, 20),
      randomTrip('twenty-alternatives', 18, 20, alternativesPercent: 30),
      randomTrip('twenty-two-same-points', 19, 22, samePointPercent: 25),
      randomTrip('twenty-five-segments', 20, 25, legPercent: 20),
      randomTrip('twenty-eight-clustered', 21, 28, clustered: true),
      randomTrip('thirty', 22, 30),
      randomTrip('thirty-three-mixed', 23, 33,
          legPercent: 10, unmeasuredPercent: 10, alternativesPercent: 10),
      randomTrip('thirty-six', 24, 36),
      randomTrip('forty', 25, 40),
      randomTrip('forty-round-trip', 26, 40, roundTrip: true),
      randomTrip('earth-five', 27, 5, spanKm: 20000),
      randomTrip('earth-fourteen', 28, 14, spanKm: 20000),
      randomTrip('earth-thirty', 29, 30, spanKm: 20000),
      randomTrip('nothing-located', 30, 6, unmeasuredPercent: 100),
    ];

/// Every day's answer, a line per choice: the order as the trip's old track
/// numbers with the metres before and after, or "-" when the choice suggests
/// nothing; and per day what the tap would say.
Future<Map<String, String>> orderGoldenOf(List<TripDay> days) async {
  final lines = <String, String>{};
  for (final day in days) {
    final c = (await orderByDistanceChoices(day.arrangement, day.segments))!;
    final number = {
      for (var i = 0; i < day.tracks.length; i++) day.tracks[i].id: i,
    };
    lines['${day.name} tap'] =
        '${c.located}/${c.total} located, ${c.reason?.name ?? 'a suggestion'}';
    for (final choice in OrderChoice.all) {
      final r = c.resultFor(choice);
      lines['${day.name} ${choiceCode(choice)}'] = r == null
          ? '-'
          : '${[for (final k in r.rowKeys) number[k]].join(' ')}'
              ' | ${r.previousLengthMetres} > ${r.lengthMetres}';
    }
  }
  return lines;
}
