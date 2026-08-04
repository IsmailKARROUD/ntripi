// features/itineraries/domain/recommended_period.dart — the author's answer to
// "when should I go?".
//
// Three independent optional parts: travel windows, a weekday set, and a
// one-line "why". Any one may be filled without the others.
//
// A window carries NO YEAR. It is a recurring annual span, so fromMonth=9 /
// toMonth=3 reads as "September through March" — a wrap-around, not reversed
// input. That is also why [windowsFromMonths] treats the month ring as
// circular: Jan–Mar plus Sep–Dec is a single Sep–Mar run, not two windows.
//
// The editor never lets the author build overlapping windows: it edits a set of
// months and derives windows from the contiguous runs, so two windows always
// have at least one unselected month between them. The backend enforces the
// same rule (schemas/itinerary.py) rather than trusting the client, which is
// why [windowsFromMonths] output is always accepted as-is.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart' as intl;
import 'package:social_flutter/l10n/app_localizations.dart';

/// Days per month with February at 29 — a window has no year, so a boundary on
/// the leap day is a real choice. Mirrors _DAYS_IN_MONTH in the backend schema.
const _daysInMonth = <int, int>{
  1: 31, 2: 29, 3: 31, 4: 30, 5: 31, 6: 30,
  7: 31, 8: 31, 9: 30, 10: 31, 11: 30, 12: 31,
};

/// How many days the day picker may offer for [month]. February gets 29.
int daysInMonth(int month) => _daysInMonth[month] ?? 31;

/// Any year works for formatting since none is stored; 2024 is a leap year, so
/// 29 February renders instead of rolling over to 1 March.
const _formatYear = 2024;

/// 1 January 2024 was a Monday, so DateTime(2024, 1, n).weekday == n for 1..7 —
/// the same ISO numbering the wire format and the backend use.
DateTime _weekdayDate(int isoWeekday) => DateTime(_formatYear, 1, isoWeekday);

/// One recurring annual travel window.
///
/// [fromDay] / [toDay] are optional refinements of the window's first and last
/// month; null means "the whole of that month".
class PeriodWindow {
  final int fromMonth;
  final int? fromDay;
  final int toMonth;
  final int? toDay;

  const PeriodWindow({
    required this.fromMonth,
    this.fromDay,
    required this.toMonth,
    this.toDay,
  });

  factory PeriodWindow.fromJson(Map<String, dynamic> json) => PeriodWindow(
        fromMonth: json['from_month'] as int,
        fromDay: json['from_day'] as int?,
        toMonth: json['to_month'] as int,
        toDay: json['to_day'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'from_month': fromMonth,
        'from_day': fromDay,
        'to_month': toMonth,
        'to_day': toDay,
      };

  PeriodWindow copyWith({
    int? fromMonth,
    int? toMonth,
    // Explicit clear — the `??` fallback can't null a field, only replace it,
    // and "no day" is the meaningful default rather than an absent value.
    bool clearDays = false,
    int? fromDay,
    int? toDay,
  }) =>
      PeriodWindow(
        fromMonth: fromMonth ?? this.fromMonth,
        fromDay: clearDays ? null : (fromDay ?? this.fromDay),
        toMonth: toMonth ?? this.toMonth,
        toDay: clearDays ? null : (toDay ?? this.toDay),
      );

  /// True when neither edge has been refined to an exact day.
  bool get isWholeMonths => fromDay == null && toDay == null;

  /// A single unrefined month, e.g. the author tapped only June.
  bool get isSingleMonth => fromMonth == toMonth && isWholeMonths;

  /// Localized label, e.g. "September – March", "1 Sep – 15 Mar", "June".
  ///
  /// Full month names read better on their own, but mixing "September" with
  /// "15 Mar" in one range does not — so a window with any day set uses the
  /// short month form on both edges.
  String label(String localeName) {
    if (isSingleMonth) {
      return intl.DateFormat.MMMM(localeName)
          .format(DateTime(_formatYear, fromMonth));
    }
    final short = !isWholeMonths;
    return '${_edge(fromMonth, fromDay, localeName, short)}'
        ' – '
        '${_edge(toMonth, toDay, localeName, short)}';
  }

  static String _edge(int month, int? day, String localeName, bool short) {
    if (day == null) {
      final format = short
          ? intl.DateFormat.MMM(localeName)
          : intl.DateFormat.MMMM(localeName);
      return format.format(DateTime(_formatYear, month));
    }
    return intl.DateFormat.MMMd(localeName)
        .format(DateTime(_formatYear, month, day));
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodWindow &&
      other.fromMonth == fromMonth &&
      other.fromDay == fromDay &&
      other.toMonth == toMonth &&
      other.toDay == toDay;

  @override
  int get hashCode => Object.hash(fromMonth, fromDay, toMonth, toDay);

  @override
  String toString() => 'PeriodWindow($fromMonth/$fromDay → $toMonth/$toDay)';
}

/// The full recommended period: windows, weekdays, and the "why".
class RecommendedPeriod {
  /// Sorted by [PeriodWindow.fromMonth]; never overlapping or adjacent.
  final List<PeriodWindow> windows;

  /// ISO weekday numbers, 1 = Monday … 7 = Sunday, sorted. Empty = unset.
  final List<int> weekdays;

  final String? note;

  const RecommendedPeriod({
    this.windows = const [],
    this.weekdays = const [],
    this.note,
  });

  /// Null when the itinerary carries no period at all — including every summary
  /// payload, which never sends these keys.
  static RecommendedPeriod? fromItineraryJson(Map<String, dynamic> json) {
    final rawWindows = json['recommended_periods'] as List<dynamic>?;
    final rawWeekdays = json['recommended_weekdays'] as List<dynamic>?;
    final note = json['recommended_period_note'] as String?;
    if (rawWindows == null && rawWeekdays == null && note == null) return null;

    final period = RecommendedPeriod(
      windows: rawWindows
              ?.map((w) => PeriodWindow.fromJson(w as Map<String, dynamic>))
              .toList() ??
          const [],
      weekdays: rawWeekdays?.map((d) => d as int).toList() ?? const [],
      note: note,
    );
    return period.isEmpty ? null : period;
  }

  /// PATCH request body. All three keys are always present: the server uses
  /// `exclude_unset`, so an omitted key means "leave it alone" and only an
  /// explicit null clears a value.
  Map<String, dynamic> toPayload() => {
        'recommended_periods':
            windows.isEmpty ? null : windows.map((w) => w.toJson()).toList(),
        'recommended_weekdays': weekdays.isEmpty ? null : weekdays,
        'recommended_period_note': _trimmedNote,
      };

  String? get _trimmedNote {
    final trimmed = note?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  bool get isEmpty =>
      windows.isEmpty && weekdays.isEmpty && _trimmedNote == null;

  RecommendedPeriod copyWith({
    List<PeriodWindow>? windows,
    List<int>? weekdays,
    String? note,
    // Explicit clear — the `??` fallback can't null a field, only replace it.
    bool clearNote = false,
  }) =>
      RecommendedPeriod(
        windows: windows ?? this.windows,
        weekdays: weekdays ?? this.weekdays,
        note: clearNote ? null : (note ?? this.note),
      );

  /// All window labels joined, e.g. "1 Sep – 15 Mar · June". Null when unset.
  String? dateLabel(String localeName) => windows.isEmpty
      ? null
      : windows.map((w) => w.label(localeName)).join(' · ');

  /// e.g. "Weekdays", "Weekends", "Mon, Wed, Fri". Null when unset.
  ///
  /// All seven days returns null on purpose: "any day of the week" is the
  /// default and says nothing worth a line of screen space.
  String? weekdaysLabel(AppLocalizations l10n, String localeName) {
    if (weekdays.isEmpty || weekdays.length == 7) return null;
    final selected = weekdays.toSet();
    if (setEqualsInts(selected, const {1, 2, 3, 4, 5})) return l10n.periodWeekdays;
    if (setEqualsInts(selected, const {6, 7})) return l10n.periodWeekends;
    final format = intl.DateFormat.E(localeName);
    return (weekdays.toList()..sort())
        .map((d) => format.format(_weekdayDate(d)))
        .join(', ');
  }

  /// One line for a collapsed picker row — dates if any, else weekdays, else
  /// the note. Null when nothing is set.
  String? shortLabel(AppLocalizations l10n, String localeName) =>
      dateLabel(localeName) ??
      weekdaysLabel(l10n, localeName) ??
      _trimmedNote;

  @override
  bool operator ==(Object other) =>
      other is RecommendedPeriod &&
      listEquals(other.windows, windows) &&
      listEquals(other.weekdays, weekdays) &&
      other._trimmedNote == _trimmedNote;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(windows), Object.hashAll(weekdays), _trimmedNote);
}

/// Set equality without pulling in collection/SetEquality for two int sets.
bool setEqualsInts(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);

int _prevMonth(int month) => month == 1 ? 12 : month - 1;
int _nextMonth(int month) => month == 12 ? 1 : month + 1;

/// Groups a set of selected months into contiguous windows, wrapping the year.
///
/// This is what makes overlapping windows impossible in the editor: the month
/// set is the source of truth, so selecting Jan–Jun and then Mar–Jul is just
/// {1…7} and yields exactly one Jan–Jul window. Two windows can only come out
/// of this with an unselected month between them, which is precisely the shape
/// the backend accepts.
List<PeriodWindow> windowsFromMonths(Set<int> months) {
  final selected = months.where((m) => m >= 1 && m <= 12).toSet();
  if (selected.isEmpty) return const [];
  // Every month selected has no run boundary to start from — special-cased so
  // the walk below cannot spin forever looking for one.
  if (selected.length == 12) {
    return const [PeriodWindow(fromMonth: 1, toMonth: 12)];
  }

  final starts = selected.where((m) => !selected.contains(_prevMonth(m))).toList()
    ..sort();
  return [
    for (final start in starts)
      PeriodWindow(fromMonth: start, toMonth: _runEnd(selected, start)),
  ];
}

int _runEnd(Set<int> selected, int start) {
  var end = start;
  while (selected.contains(_nextMonth(end))) {
    end = _nextMonth(end);
  }
  return end;
}

/// Every month the given windows cover — the inverse of [windowsFromMonths],
/// used to re-open the editor's grid on a saved value.
Set<int> monthsFromWindows(List<PeriodWindow> windows) {
  final months = <int>{};
  for (final window in windows) {
    var month = window.fromMonth;
    while (true) {
      months.add(month);
      if (month == window.toMonth) break;
      month = _nextMonth(month);
    }
  }
  return months;
}
