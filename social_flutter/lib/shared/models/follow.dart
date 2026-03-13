// shared/models/follow.dart — Dart data classes for follow-related API responses.

/// Represents a follow relationship record.
class Follow {
  final String id;
  final String followerId;
  final String followingId;

  /// 'pending' or 'accepted'
  final String status;

  final DateTime createdAt;

  const Follow({
    required this.id,
    required this.followerId,
    required this.followingId,
    required this.status,
    required this.createdAt,
  });

  factory Follow.fromJson(Map<String, dynamic> json) {
    return Follow(
      id: json['id'] as String,
      followerId: json['follower_id'] as String,
      followingId: json['following_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'follower_id': followerId,
      'following_id': followingId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
}

/// A single item in the "pending follow requests" list.
/// This is what the backend returns from GET /users/me/follow-requests.
/// It combines the Follow record data with the follower's profile info
/// so the UI can render each request without additional API calls.
class FollowRequestItem {
  /// The Follow record's ID — needed to accept or reject via the API.
  final String followId;

  final String followerId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime requestedAt;

  const FollowRequestItem({
    required this.followId,
    required this.followerId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.requestedAt,
  });

  factory FollowRequestItem.fromJson(Map<String, dynamic> json) {
    return FollowRequestItem(
      followId: json['follow_id'] as String,
      followerId: json['follower_id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      requestedAt: DateTime.parse(json['requested_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'follow_id': followId,
      'follower_id': followerId,
      'username': username,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'requested_at': requestedAt.toIso8601String(),
    };
  }
}

/// A single item in the followers or following list.
/// Matches the backend's FollowerListItem schema returned by
/// GET /users/{id}/followers and GET /users/{id}/following.
///
/// This is a compact profile view — it only contains the fields needed
/// to render a list row (avatar, name, privacy badge). It does NOT include
/// follower counts or bio; those are loaded separately on the full profile screen.
class FollowerListItem {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  /// Whether this user's account is private.
  /// Used to show the lock icon next to their name in the list.
  final bool isPrivate;

  const FollowerListItem({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.isPrivate,
  });

  factory FollowerListItem.fromJson(Map<String, dynamic> json) {
    return FollowerListItem(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      // Default to false if the field is unexpectedly absent — safe fallback
      // since the worst outcome is not showing a lock icon.
      isPrivate: json['is_private'] as bool? ?? false,
    );
  }
}
