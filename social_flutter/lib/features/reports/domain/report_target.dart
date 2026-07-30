// features/reports/domain/report_target.dart — what is being reported.
//
// Stops, annotations and transport legs are reported as their PARENT itinerary
// with the fragment noted in the report text: hiding is itinerary-level, so a
// sub-target would have no read path that could act on it. [ReportTarget.stop]
// exists to build that note, not as a separate backend target type.

/// Backend target types (must match REPORT_TARGET_TYPES in
/// app/models/content_report.py).
enum ReportTargetKind { itinerary, rating, user }

class ReportTarget {
  final ReportTargetKind kind;
  final String id;

  /// A stop within [id] when the report is about one specific stop. Sent as a
  /// prefix on the notes so a moderator can find it inside the itinerary.
  final String? stopId;

  const ReportTarget._(this.kind, this.id, {this.stopId});

  const ReportTarget.itinerary(String itineraryId)
      : this._(ReportTargetKind.itinerary, itineraryId);

  const ReportTarget.stop(String itineraryId, String stopId)
      : this._(ReportTargetKind.itinerary, itineraryId, stopId: stopId);

  const ReportTarget.rating(String ratingId)
      : this._(ReportTargetKind.rating, ratingId);

  const ReportTarget.user(String userId) : this._(ReportTargetKind.user, userId);

  String get wireKind => kind.name;

  /// Prefixes the reporter's notes with the stop reference when there is one.
  String? notesWithContext(String? notes) {
    final trimmed = notes?.trim();
    if (stopId == null) return (trimmed?.isEmpty ?? true) ? null : trimmed;
    return '[stop:$stopId] ${trimmed ?? ''}'.trim();
  }
}

/// Canonical report reasons, ordered by severity with spam first — the most
/// common and least severe, so the list opens on what most people actually
/// need. Must match REPORT_REASONS in app/models/content_report.py.
const kReportReasons = <String>[
  'spam',
  'harassment',
  'hate_speech',
  'sexual_content',
  'violence_threat',
  'csam',
  'other',
];
