// A trip's length as the app shows it (domain/trip_length.dart): the author's
// recommended minimum time to spend when set — "at least", marked "3d+" — else
// the length computed from the stops. One decision for the trip page's chip,
// the trip cards, the share caption and the Itineraries tab's total. Also the
// spelled-out form the edit rows use ("At least 3 days"), the wheel's
// conversion, and the model field the server appends to every trip payload.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/trip_length.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/utils/duration_format.dart';
import 'package:ntripi/shared/widgets/duration_picker_sheet.dart';

import '../support/trip_json.dart';

const _day = 24 * 60;

final _en = lookupAppLocalizations(const Locale('en'));
final _ar = lookupAppLocalizations(const Locale('ar'));
final _zh = lookupAppLocalizations(const Locale('zh'));
final _fr = lookupAppLocalizations(const Locale('fr'));

Itinerary _trip({int computed = 0, int? recommended}) => Itinerary.fromJson({
      ...tripJson(totalDurationMin: computed),
      'recommended_duration_min': recommended,
    });

void main() {
  group('TripLength.of', () {
    test('Given the author set a minimum, Then it is the length, marked "+"',
        () {
      final length = TripLength.of(_trip(computed: 90, recommended: 3 * _day));
      expect(length.minutes, 3 * _day);
      expect(length.atLeast, isTrue);
      expect(length.compact(_en), '3d+');
    });

    test('Given none, Then the computed length shows as before, unmarked', () {
      final length = TripLength.of(_trip(computed: 90));
      expect(length.atLeast, isFalse);
      expect(length.compact(_en), '1h 30min');
    });

    test('Given nothing at all, Then the dash, never "—+"', () {
      expect(TripLength.of(_trip()).compact(_en), '—');
    });

    test('Given another language, Then its own way of saying "or more"', () {
      final trip = _trip(recommended: 3 * _day);
      expect(TripLength.of(trip).compact(_ar), '3ي فأكثر');
      expect(TripLength.of(trip).compact(_zh), '3天以上');
      expect(TripLength.of(trip).compact(_fr), '3j+');
    });
  });

  group('TripLength.ofAll', () {
    test(
        'Given trips with and without a minimum, Then each counts by its own '
        'length, and the total is a minimum', () {
      final total = TripLength.ofAll([
        _trip(computed: 120, recommended: 2 * _day),
        _trip(computed: 180),
      ]);
      expect(total.minutes, 2 * _day + 180);
      expect(total.atLeast, isTrue);
    });

    test('Given no minimum anywhere, Then the total is unmarked', () {
      final total = TripLength.ofAll([_trip(computed: 60), _trip(computed: 30)]);
      expect(total.minutes, 90);
      expect(total.atLeast, isFalse);
      expect(total.mark('1h', _en), '1h');
    });
  });

  group('formatDurationLong — the edit rows\' "At least …"', () {
    test('Given English, Then each unit in its plural, comma-separated', () {
      expect(formatDurationLong(3 * _day, _en), '3 days');
      expect(formatDurationLong(_day + 60 + 30, _en), '1 day, 1 hour, 30 minutes');
      expect(formatDurationLong(1, _en), '1 minute');
      expect(_en.recommendedTimeAtLeast(formatDurationLong(3 * _day, _en)),
          'At least 3 days');
    });

    test('Given the wheel\'s largest value, Then days — never years', () {
      expect(formatDurationLong(365 * _day + 23 * 60 + 59, _en),
          '365 days, 23 hours, 59 minutes');
    });

    test('Given Arabic, Then each number takes its own form, joined by و', () {
      expect(formatDurationLong(_day, _ar), 'يوم واحد');
      expect(formatDurationLong(2 * _day, _ar), 'يومان');
      expect(formatDurationLong(4 * _day + 4 * 60, _ar), '4 أيام و4 ساعات');
      expect(formatDurationLong(11 * _day, _ar), '11 يومًا');
      expect(formatDurationLong(100 * _day, _ar), '100 يوم');
    });

    test('Given Chinese and French, Then their own units', () {
      expect(formatDurationLong(3 * _day + 4 * 60, _zh), '3 天 4 小时');
      expect(formatDurationLong(2 * _day + 1, _fr), '2 jours, 1 minute');
    });

    test('Given nothing, Then the fallback', () {
      expect(formatDurationLong(null, _en), '—');
      expect(formatDurationLong(0, _en), '—');
    });
  });

  group('the wheel\'s conversion', () {
    test('Given minutes, Then days, hours and minutes, and back', () {
      final parts = durationPartsOf(3 * _day + 4 * 60 + 5);
      expect(parts, (days: 3, hours: 4, minutes: 5));
      expect(minutesOrNull(parts), 3 * _day + 4 * 60 + 5);
    });

    test('Given null, Then every wheel at zero; every wheel at zero clears', () {
      expect(durationPartsOf(null), (days: 0, hours: 0, minutes: 0));
      expect(minutesOrNull((days: 0, hours: 0, minutes: 0)), isNull);
    });
  });

  group('Itinerary.recommendedDurationMin', () {
    test('Given a payload with it, Then it is read, written back and kept by '
        'the list row', () {
      final trip = _trip(recommended: 90);
      expect(trip.recommendedDurationMin, 90);
      expect(trip.toJson()['recommended_duration_min'], 90);
      expect(trip.summary.recommendedDurationMin, 90);
    });

    test('Given a payload without it (an older server), Then null', () {
      expect(Itinerary.fromJson(tripJson()).recommendedDurationMin, isNull);
    });

    test('Given copyWith, Then it replaces it, and clears it only when asked',
        () {
      final trip = _trip(recommended: 90);
      expect(trip.copyWith(recommendedDurationMin: 120).recommendedDurationMin,
          120);
      expect(trip.copyWith(title: 'x').recommendedDurationMin, 90);
      expect(
          trip.copyWith(clearRecommendedDurationMin: true).recommendedDurationMin,
          isNull);
    });
  });
}
