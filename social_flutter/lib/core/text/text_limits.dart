// core/text/text_limits.dart — the server's cap on each text a user writes.
//
// One number per field, the same as the API's Pydantic `max_length`:
// social_api/test/test_text_limits.py reads this file and fails when a number
// here and the API's request schema disagree. A field shows its count from 90%
// of its cap and holds Save back past it (shared/widgets/text_rules.dart) —
// nothing typed or pasted is ever cut.

/// Caps in characters as the server counts them: Unicode code points of the
/// trimmed text ([textLength]).
abstract final class TextLimits {
  // A trip.
  static const itineraryTitle = 200;
  static const itineraryDescription = 10000;
  static const periodNote = 4000;

  // A stop.
  static const stopName = 200;
  static const stopAddress = 400;
  static const stopNotes = 2000;
  static const mapLink = 500;

  /// The place search box — the Google search proxy's input and a stop's
  /// stored search text share it.
  static const placeSearch = 200;

  /// A trip-wide or stop note (both annotation tables).
  static const annotation = 2000;

  // A transport leg.
  static const legLine = 30;
  static const legDirection = 200;
  static const legNotes = 1000;

  static const ratingNote = 2000;

  // A profile.
  static const displayName = 50;
  static const bio = 500;
  static const username = 30;

  // Texts only the operator reads.
  static const reportNotes = 2000;
  static const appealReason = 2000;
  static const bugMessage = 2000;
}

/// [text]'s length as the server counts it: every form sends the text trimmed,
/// and Pydantic counts code points — Dart's `length` counts UTF-16 units, so an
/// emoji would count twice.
int textLength(String text) => text.trim().runes.length;
