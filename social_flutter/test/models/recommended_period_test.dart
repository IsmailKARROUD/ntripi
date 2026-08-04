// test/models/recommended_period_test.dart
//
// The month grid is what makes overlapping travel windows impossible, so the
// grouping helpers carry the whole invariant: whatever windowsFromMonths emits
// must be something the backend's non-overlap/non-adjacency validator accepts.
// These tests pin that, plus the wrap-around semantics (a window has no year)
// and the wire round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';

void main() {
  // DateFormat with an explicit locale needs symbols loaded. The running app
  // gets these from GlobalMaterialLocalizations; a pure-Dart test does not.
  setUpAll(initializeDateFormatting);

  group('windowsFromMonths', () {
    test('empty selection produces no windows', () {
      expect(windowsFromMonths({}), isEmpty);
    });

    test('a single month becomes a one-month window', () {
      expect(
        windowsFromMonths({6}),
        [const PeriodWindow(fromMonth: 6, toMonth: 6)],
      );
    });

    test('contiguous months become one window', () {
      expect(
        windowsFromMonths({4, 5, 6}),
        [const PeriodWindow(fromMonth: 4, toMonth: 6)],
      );
    });

    test('wraps the year boundary into a single Sep-Mar window', () {
      // Jan-Mar plus Sep-Dec is contiguous through December -> January.
      expect(
        windowsFromMonths({1, 2, 3, 9, 10, 11, 12}),
        [const PeriodWindow(fromMonth: 9, toMonth: 3)],
      );
    });

    test('all twelve months collapse to one Jan-Dec window', () {
      expect(
        windowsFromMonths({for (var m = 1; m <= 12; m++) m}),
        [const PeriodWindow(fromMonth: 1, toMonth: 12)],
      );
    });

    test('scattered months become separate single-month windows, sorted', () {
      expect(windowsFromMonths({9, 4, 6}), [
        const PeriodWindow(fromMonth: 4, toMonth: 4),
        const PeriodWindow(fromMonth: 6, toMonth: 6),
        const PeriodWindow(fromMonth: 9, toMonth: 9),
      ]);
    });

    test('ignores months outside 1-12', () {
      expect(
        windowsFromMonths({0, 6, 13}),
        [const PeriodWindow(fromMonth: 6, toMonth: 6)],
      );
    });
  });

  group('overlap is structurally impossible', () {
    test('Jan-Jun plus Mar-Jul is one Jan-Jul window, not two', () {
      // The exact case a user would try to create by hand: the grid holds a
      // month SET, so the second range just extends the first.
      final months = {1, 2, 3, 4, 5, 6}..addAll({3, 4, 5, 6, 7});
      expect(
        windowsFromMonths(months),
        [const PeriodWindow(fromMonth: 1, toMonth: 7)],
      );
    });

    test('Jan-Mar plus Apr-Jun is one Jan-Jun window — adjacency merges too', () {
      final months = {1, 2, 3}..addAll({4, 5, 6});
      expect(
        windowsFromMonths(months),
        [const PeriodWindow(fromMonth: 1, toMonth: 6)],
      );
    });

    test('output is never overlapping or adjacent, for every month subset', () {
      // Exhaustive over all 4096 subsets: no emitted list can be one the
      // backend validator would reject.
      for (var mask = 0; mask < 4096; mask++) {
        final months = <int>{
          for (var m = 1; m <= 12; m++)
            if (mask & (1 << (m - 1)) != 0) m,
        };
        final windows = windowsFromMonths(months);

        final claimed = <int>{};
        for (final window in windows) {
          final covered = monthsFromWindows([window]);
          expect(claimed.intersection(covered), isEmpty,
              reason: 'windows overlap for $months');
          claimed.addAll(covered);
          // The month right after a window must be free, or the two windows
          // are really one — unless this window covers the entire year.
          if (covered.length < 12) {
            final after = window.toMonth % 12 + 1;
            expect(months.contains(after), isFalse,
                reason: 'window is adjacent to another for $months');
          }
        }
      }
    });

    test('at most six windows can ever be produced', () {
      // Matches _MAX_PERIOD_WINDOWS on the backend.
      var worst = 0;
      for (var mask = 0; mask < 4096; mask++) {
        final months = <int>{
          for (var m = 1; m <= 12; m++)
            if (mask & (1 << (m - 1)) != 0) m,
        };
        worst = worst > windowsFromMonths(months).length
            ? worst
            : windowsFromMonths(months).length;
      }
      expect(worst, 6);
    });
  });

  group('monthsFromWindows', () {
    test('round-trips through windowsFromMonths', () {
      for (final months in [
        <int>{},
        {6},
        {4, 5, 6},
        {1, 2, 3, 9, 10, 11, 12},
        {4, 6, 9},
        {for (var m = 1; m <= 12; m++) m},
      ]) {
        expect(monthsFromWindows(windowsFromMonths(months)), months);
      }
    });

    test('expands a wrap-around window through December', () {
      expect(
        monthsFromWindows([const PeriodWindow(fromMonth: 11, toMonth: 2)]),
        {11, 12, 1, 2},
      );
    });
  });

  group('wire format', () {
    test('fromItineraryJson round-trips through toPayload', () {
      final json = {
        'recommended_periods': [
          {'from_month': 9, 'from_day': 1, 'to_month': 3, 'to_day': 15},
        ],
        'recommended_weekdays': [6, 7],
        'recommended_period_note': 'Fewer crowds',
      };

      final period = RecommendedPeriod.fromItineraryJson(json)!;
      expect(period.windows.single.fromMonth, 9);
      expect(period.windows.single.toDay, 15);
      expect(period.weekdays, [6, 7]);
      expect(period.toPayload(), json);
    });

    test('is null when the payload carries none of the three keys', () {
      // Every summary/list payload looks like this — it must not become an
      // empty period, or the owner's edit row would claim something was set.
      expect(RecommendedPeriod.fromItineraryJson({'title': 'A trip'}), isNull);
    });

    test('is null when all three keys are present but empty', () {
      expect(
        RecommendedPeriod.fromItineraryJson({
          'recommended_periods': null,
          'recommended_weekdays': null,
          'recommended_period_note': null,
        }),
        isNull,
      );
    });

    test('toPayload always emits all three keys, so a clear reaches the server', () {
      // The PATCH uses exclude_unset: an omitted key means "leave it alone",
      // so clearing requires an explicit null rather than an absent key.
      expect(const RecommendedPeriod().toPayload(), {
        'recommended_periods': null,
        'recommended_weekdays': null,
        'recommended_period_note': null,
      });
    });

    test('a whitespace-only note counts as unset', () {
      const period = RecommendedPeriod(note: '   ');
      expect(period.isEmpty, isTrue);
      expect(period.toPayload()['recommended_period_note'], isNull);
    });
  });

  group('labels', () {
    test('an unrefined single month reads as the full month name', () {
      const window = PeriodWindow(fromMonth: 6, toMonth: 6);
      expect(window.label('en'), 'June');
      expect(window.label('fr'), 'juin');
    });

    test('a month range uses full month names on both edges', () {
      const window = PeriodWindow(fromMonth: 9, toMonth: 3);
      expect(window.label('en'), 'September – March');
    });

    test('any exact day switches both edges to the short form', () {
      // Mixing "September" with "15 Mar" in one range reads badly.
      const window =
          PeriodWindow(fromMonth: 9, toMonth: 3, toDay: 15);
      final label = window.label('en');
      expect(label, contains('Sep'));
      expect(label, isNot(contains('September')));
      expect(label, contains('15'));
    });

    test('dateLabel joins multiple windows', () {
      const period = RecommendedPeriod(windows: [
        PeriodWindow(fromMonth: 4, toMonth: 4),
        PeriodWindow(fromMonth: 9, toMonth: 9),
      ]);
      expect(period.dateLabel('en'), 'April · September');
    });

    test('dateLabel is null with no windows', () {
      expect(const RecommendedPeriod().dateLabel('en'), isNull);
    });
  });

  group('daysInMonth', () {
    test('February allows the leap day — a window carries no year', () {
      expect(daysInMonth(2), 29);
    });

    test('short months stop at 30', () {
      expect(daysInMonth(4), 30);
      expect(daysInMonth(1), 31);
    });
  });

  group('equality', () {
    test('two periods with the same content are equal', () {
      const a = RecommendedPeriod(
        windows: [PeriodWindow(fromMonth: 4, toMonth: 6)],
        weekdays: [6, 7],
        note: 'why',
      );
      const b = RecommendedPeriod(
        windows: [PeriodWindow(fromMonth: 4, toMonth: 6)],
        weekdays: [6, 7],
        note: 'why',
      );
      // The form's unsaved-changes guard compares snapshots by value, so this
      // is what stops "open the picker, change nothing" from looking dirty.
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a changed day makes them unequal', () {
      const a = RecommendedPeriod(windows: [PeriodWindow(fromMonth: 4, toMonth: 6)]);
      const b = RecommendedPeriod(
        windows: [PeriodWindow(fromMonth: 4, toMonth: 6, fromDay: 15)],
      );
      expect(a, isNot(b));
    });
  });
}
