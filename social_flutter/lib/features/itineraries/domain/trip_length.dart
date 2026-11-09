// domain/trip_length.dart — how long a trip takes, as the app shows it.
//
// The author's recommended minimum time to spend
// (Itinerary.recommendedDurationMin) when they set one — "at least", marked
// "3d+" — otherwise the length the server computes from the stops and the
// transport (total_duration_min), which adds every stop, parallel alternatives
// included, and so can only ever guess. One decision for every place a trip's
// length shows: the trip page's chip, a trip card, the share caption and the
// Itineraries tab's total. Never format a trip's length any other way.

import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/utils/duration_format.dart';

class TripLength {
  const TripLength(this.minutes, {required this.atLeast});

  /// The trip's length — or several trips' together.
  final int minutes;

  /// An author's minimum stands behind it (or behind one of the trips added
  /// up), so the true length is this or more.
  final bool atLeast;

  factory TripLength.of(Itinerary trip) {
    final recommended = trip.recommendedDurationMin;
    return recommended != null
        ? TripLength(recommended, atLeast: true)
        : TripLength(trip.totalDurationMin, atLeast: false);
  }

  /// Several trips added up, each by [TripLength.of].
  factory TripLength.ofAll(Iterable<Itinerary> trips) {
    var minutes = 0;
    var atLeast = false;
    for (final trip in trips) {
      final length = TripLength.of(trip);
      minutes += length.minutes;
      atLeast = atLeast || length.atLeast;
    }
    return TripLength(minutes, atLeast: atLeast);
  }

  /// [text], marked as a minimum when it is one: "3d" becomes "3d+".
  String mark(String text, AppLocalizations l10n) =>
      atLeast && minutes > 0 ? l10n.tripLengthAtLeastShort(text) : text;

  /// "3d", or "3d+" for a minimum — a chip, a card, a caption.
  String compact(AppLocalizations l10n) =>
      mark(formatDuration(minutes, l10n), l10n);
}
