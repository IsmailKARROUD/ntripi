// features/reports/domain/report_target.dart — what is being reported.
//
// Stops, annotations and transport legs are reported as their PARENT itinerary
// with the fragment noted in the report text: hiding is itinerary-level, so a
// sub-target would have no read path that could act on it. [ReportTarget.stop]
// and the annotation constructors exist to build that note, not as separate
// backend target types.

/// Backend target types (must match REPORT_TARGET_TYPES in
/// app/models/content_report.py).
enum ReportTargetKind { itinerary, rating, user }

class ReportTarget {
  final ReportTargetKind kind;
  final String id;

  /// A stop within [id] when the report is about one specific stop. Sent as a
  /// prefix on the notes so a moderator can find it inside the itinerary.
  final String? stopId;

  /// An annotation within [id]; stop-level when [stopId] is set too, otherwise
  /// itinerary-level. Same purpose as [stopId] — it only builds the note.
  final String? annotationId;

  const ReportTarget._(this.kind, this.id, {this.stopId, this.annotationId});

  const ReportTarget.itinerary(String itineraryId)
      : this._(ReportTargetKind.itinerary, itineraryId);

  const ReportTarget.stop(String itineraryId, String stopId)
      : this._(ReportTargetKind.itinerary, itineraryId, stopId: stopId);

  const ReportTarget.stopAnnotation(
    String itineraryId,
    String stopId,
    String annotationId,
  ) : this._(ReportTargetKind.itinerary, itineraryId,
            stopId: stopId, annotationId: annotationId);

  const ReportTarget.itineraryAnnotation(
    String itineraryId,
    String annotationId,
  ) : this._(ReportTargetKind.itinerary, itineraryId,
            annotationId: annotationId);

  const ReportTarget.rating(String ratingId)
      : this._(ReportTargetKind.rating, ratingId);

  const ReportTarget.user(String userId) : this._(ReportTargetKind.user, userId);

  String get wireKind => kind.name;

  bool get isAnnotation => annotationId != null;
  bool get isStop => stopId != null && annotationId == null;

  /// Prefixes the reporter's notes with the fragment reference when there is
  /// one — `[stop:x]`, `[stop:x annotation:y]` or `[annotation:y]`.
  String? notesWithContext(String? notes) {
    final trimmed = notes?.trim();
    final fragment = [
      if (stopId != null) 'stop:$stopId',
      if (annotationId != null) 'annotation:$annotationId',
    ].join(' ');
    if (fragment.isEmpty) return (trimmed?.isEmpty ?? true) ? null : trimmed;
    return '[$fragment] ${trimmed ?? ''}'.trim();
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
