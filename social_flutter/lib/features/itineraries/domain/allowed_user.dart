// features/itineraries/domain/allowed_user.dart — AllowedUser domain model.
//
// Represents a single entry in the restricted itinerary allowlist.
// Returned by GET/POST /itineraries/{id}/allowed-users.

class AllowedUser {
  final String userId;
  final String username;
  final String? displayName;
  final DateTime createdAt;

  const AllowedUser({
    required this.userId,
    required this.username,
    this.displayName,
    required this.createdAt,
  });

  factory AllowedUser.fromJson(Map<String, dynamic> json) {
    return AllowedUser(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
