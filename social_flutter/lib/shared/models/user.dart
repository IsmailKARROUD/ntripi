// shared/models/user.dart — Dart data class for a User.
//
// Design decisions:
//   - Immutable (all fields are final): prevents accidental mutations.
//   - fromJson factory: single point for JSON deserialization. If the API
//     changes a field name, you fix it in one place.
//   - toJson: used when sending user data to the API (e.g., profile updates).
//   - isFollowing and followIsPending default to false: these are computed
//     fields added by the server only on GET /users/{id}. They don't exist
//     on profile responses for the current user, so we default them safely.
//   - All IDs are Strings (UUID strings). We avoid parsing to a UUID class
//     to keep serialization simple.

class User {
  final String id;
  final String username;

  /// Null for public profile views (other users can't see your email).
  final String? email;

  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final bool isPrivate;
  final int followersCount;
  final int followingCount;

  /// True if the currently authenticated user follows this user (accepted).
  final bool isFollowing;

  /// True if the currently authenticated user has a pending follow request.
  final bool followIsPending;

  final DateTime createdAt;

  const User({
    required this.id,
    required this.username,
    this.email,
    this.displayName,
    this.bio,
    this.avatarUrl,
    required this.isPrivate,
    required this.followersCount,
    required this.followingCount,
    this.isFollowing = false,
    this.followIsPending = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
      followIsPending: json['follow_is_pending'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime(2020),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (email != null) 'email': email,
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'is_private': isPrivate,
      'followers_count': followersCount,
      'following_count': followingCount,
      'is_following': isFollowing,
      'follow_is_pending': followIsPending,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Creates a copy of this User with specific fields changed.
  /// Used for optimistic UI updates (e.g., after following/unfollowing).
  User copyWith({
    String? id,
    String? username,
    String? email,
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    bool? followIsPending,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isPrivate: isPrivate ?? this.isPrivate,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      followIsPending: followIsPending ?? this.followIsPending,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
