// shared/models/moderation_status.dart — content moderation state.
//
// Parsed from every moderated content model. The critical rule is the fallback:
// an unrecognised value from a newer backend degrades to [approved] rather than
// throwing. A server-side addition must never break a client that is already on
// someone's phone and cannot be updated on demand.
//
// pending and flagged are internal states and are NOT surfaced to the author:
// they are visible exactly like approved content. Announcing a review that may
// come to nothing creates anxiety without giving the user anything to act on.

enum ModerationStatus {
  /// Clean, or never scanned. The default for anything unrecognised.
  approved,

  /// A provider was unavailable; published and queued for a re-check.
  pending,

  /// A classifier queued it for a moderator. Still fully visible.
  flagged,

  /// Taken down after publication. The author still sees it, with a reason and
  /// an appeal action; nobody else does.
  hidden,

  /// Blocked at write time. Only reachable for content that was live when a
  /// re-check condemned it.
  rejected;

  static ModerationStatus fromString(String? value) => switch (value) {
    'pending' => ModerationStatus.pending,
    'flagged' => ModerationStatus.flagged,
    'hidden' => ModerationStatus.hidden,
    'rejected' => ModerationStatus.rejected,
    // Includes 'approved', null, and anything a newer backend invents.
    _ => ModerationStatus.approved,
  };

  String get wireValue => name;

  /// Whether this state is shown to the author at all. Only a takedown is —
  /// see the note above about pending/flagged.
  bool get isVisibleToAuthor =>
      this == ModerationStatus.hidden || this == ModerationStatus.rejected;
}
