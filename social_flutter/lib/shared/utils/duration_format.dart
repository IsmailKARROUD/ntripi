// shared/utils/duration_format.dart — single source for compact duration text.
//
// Replaces the formattedDuration copies that lived in itinerary, stop,
// transit_segment and transport_leg so unit abbreviations stay localized
// ("2d 3h" in English, "2j 3h" in French).

import 'package:social_flutter/l10n/app_localizations.dart';

/// Formats [minutes] as a compact localized duration, e.g. "1y 2d 3h 15min".
///
/// Returns [fallback] when [minutes] is null or not positive.
String formatDuration(int? minutes, AppLocalizations l10n,
    {String fallback = '—'}) {
  if (minutes == null || minutes <= 0) return fallback;
  final years = minutes ~/ (60 * 24 * 365);
  var remaining = minutes % (60 * 24 * 365);
  final days = remaining ~/ (60 * 24);
  remaining %= 60 * 24;
  final hours = remaining ~/ 60;
  final mins = remaining % 60;
  final parts = <String>[
    if (years > 0) '$years${l10n.yearsAbbrev}',
    if (days > 0) '$days${l10n.daysLabel}',
    if (hours > 0) '$hours${l10n.hoursLabel}',
    if (mins > 0) '$mins${l10n.minutesLabel}',
  ];
  return parts.join(' ');
}
