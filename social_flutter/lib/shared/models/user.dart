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

import 'package:social_flutter/shared/models/moderation_status.dart';

class User {
  final String id;
  final String username;

  /// Null for public profile views (other users can't see your email).
  final String? email;

  /// Whether this account's email is verified. Only meaningful on the owner's
  /// own profile (GET /users/me); gates high-value actions. Verify via Google.
  final bool emailVerified;

  /// True when the account can log in with a password (not Google-only). Only
  /// present on GET /users/me; used to show/hide "Change password".
  final bool hasPassword;

  /// True when a Google login is linked. Only present on GET /users/me; with
  /// [hasPassword] it lets the delete screen offer Google as an alternative
  /// re-auth for dual-method accounts.
  final bool hasGoogle;

  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final String? coverImageUrl;
  final bool isPrivate;
  final int followersCount;
  final int followingCount;

  /// True if the currently authenticated user follows this user (accepted).
  final bool isFollowing;

  /// True if the currently authenticated user has a pending follow request.
  final bool followIsPending;

  final DateTime createdAt;

  /// ISO alpha-2 country codes for nationalities (multiple passports supported).
  final List<String>? passportCountries;

  /// ISO alpha-2 country code for primary country of residence.
  final String? residentCountry;

  /// ISO 639-1 language codes for spoken languages.
  final List<String>? languages;

  /// Moderation state of display_name + bio. Only ever populated on the owner's
  /// own GET /users/me — a public profile never carries another user's status.
  final ModerationStatus moderationStatus;

  // ── Optional in-app notification types. Owner's own GET /users/me only; a
  // public profile never carries them. Default true so an older backend that
  // omits the fields behaves as "everything on", matching the server default.
  final bool notifyRatings;
  final bool notifySaves;
  final bool notifyFollowAccepted;

  /// Returns displayName if set, else "@username".
  String get nameForDisplay => displayName ?? '@$username';

  /// Returns the @-handle form regardless of displayName.
  String get handle => '@$username';

  const User({
    required this.id,
    required this.username,
    this.email,
    this.emailVerified = false,
    this.hasPassword = false,
    this.hasGoogle = false,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.coverImageUrl,
    required this.isPrivate,
    required this.followersCount,
    required this.followingCount,
    this.isFollowing = false,
    this.followIsPending = false,
    required this.createdAt,
    this.passportCountries,
    this.residentCountry,
    this.languages,
    this.moderationStatus = ModerationStatus.approved,
    this.notifyRatings = true,
    this.notifySaves = true,
    this.notifyFollowAccepted = true,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      hasPassword: json['has_password'] as bool? ?? false,
      hasGoogle: json['has_google'] as bool? ?? false,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      isPrivate: json['is_private'] as bool? ?? true,
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
      followIsPending: json['follow_is_pending'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime(2020),
      passportCountries: (json['passport_countries'] as List?)
          ?.map((e) => e as String)
          .toList(),
      residentCountry: json['resident_country'] as String?,
      languages: (json['languages'] as List?)
          ?.map((e) => e as String)
          .toList(),
      moderationStatus:
          ModerationStatus.fromString(json['moderation_status'] as String?),
      // Absent on public profiles and on an older backend — default on, which
      // is what the server does when it has no opinion either.
      notifyRatings: json['notify_ratings'] as bool? ?? true,
      notifySaves: json['notify_saves'] as bool? ?? true,
      notifyFollowAccepted: json['notify_follow_accepted'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (email != null) 'email': email,
      'email_verified': emailVerified,
      'has_password': hasPassword,
      'has_google': hasGoogle,
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      'is_private': isPrivate,
      'followers_count': followersCount,
      'following_count': followingCount,
      'is_following': isFollowing,
      'follow_is_pending': followIsPending,
      'created_at': createdAt.toIso8601String(),
      if (passportCountries != null) 'passport_countries': passportCountries,
      if (residentCountry != null) 'resident_country': residentCountry,
      if (languages != null) 'languages': languages,
      'moderation_status': moderationStatus.wireValue,
      'notify_ratings': notifyRatings,
      'notify_saves': notifySaves,
      'notify_follow_accepted': notifyFollowAccepted,
    };
  }

  /// Creates a copy of this User with specific fields changed.
  /// Used for optimistic UI updates (e.g., after following/unfollowing).
  User copyWith({
    String? id,
    String? username,
    String? email,
    bool? emailVerified,
    bool? hasPassword,
    bool? hasGoogle,
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    String? coverImageUrl,
    bool clearCoverImageUrl = false,
    bool? isPrivate,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    bool? followIsPending,
    DateTime? createdAt,
    List<String>? passportCountries,
    String? residentCountry,
    List<String>? languages,
    ModerationStatus? moderationStatus,
    bool? notifyRatings,
    bool? notifySaves,
    bool? notifyFollowAccepted,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      hasPassword: hasPassword ?? this.hasPassword,
      hasGoogle: hasGoogle ?? this.hasGoogle,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      coverImageUrl:
          clearCoverImageUrl ? null : (coverImageUrl ?? this.coverImageUrl),
      isPrivate: isPrivate ?? this.isPrivate,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      followIsPending: followIsPending ?? this.followIsPending,
      createdAt: createdAt ?? this.createdAt,
      passportCountries: passportCountries ?? this.passportCountries,
      residentCountry: residentCountry ?? this.residentCountry,
      languages: languages ?? this.languages,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      notifyRatings: notifyRatings ?? this.notifyRatings,
      notifySaves: notifySaves ?? this.notifySaves,
      notifyFollowAccepted: notifyFollowAccepted ?? this.notifyFollowAccepted,
    );
  }
}
