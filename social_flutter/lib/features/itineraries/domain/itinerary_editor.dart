// features/itineraries/domain/itinerary_editor.dart — one person the owner has
// given permission to modify this itinerary.
//
// Mirrors AllowedUser, deliberately: the two lists look and behave the same to
// the owner, and only the owner ever manages either. The difference is what a
// row grants — reading versus writing — and that editing additionally requires
// the view right, re-checked server-side on every request.

/// Thrown when a grant is refused because the target cannot see the itinerary.
///
/// Not an error to report — a question to ask. The owner is offered view access
/// for that person, and only if they agree does the client retry with
/// `grantView: true`.
class EditorCannotViewException implements Exception {
  const EditorCannotViewException({
    required this.visibility,
    required this.canFixWithAllowlist,
  });

  /// The itinerary's current visibility, so the message can name it.
  final String? visibility;

  /// True when adding an allowlist row is enough (visibility is `restricted`).
  /// False for `only_me` and `followers`, where the fix is a visibility change
  /// the owner must make deliberately — the server will not do it for them.
  final bool canFixWithAllowlist;

  @override
  String toString() => 'EditorCannotViewException(visibility: $visibility)';
}

class ItineraryEditor {
  const ItineraryEditor({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.createdAt,
  });

  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;

  String get label =>
      (displayName?.isNotEmpty ?? false) ? displayName! : '@$username';

  factory ItineraryEditor.fromJson(Map<String, dynamic> json) => ItineraryEditor(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
