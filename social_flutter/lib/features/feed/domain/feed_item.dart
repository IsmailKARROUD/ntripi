// features/feed/domain/feed_item.dart — A single entry in the public discovery
// feed: a summary itinerary plus its owner attribution.
//
// The feed JSON is a superset of the itinerary-summary shape, so we reuse
// Itinerary.fromJson for the trip fields and parse the nested `owner` object
// (RaterInfo shape on the backend) into a lightweight FeedOwner.

import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';

/// Minimal author info shown on a feed card. Fields are nullable because the
/// owner may have deleted their account (the backend RaterInfo is all-Optional).
class FeedOwner {
  final String? userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const FeedOwner({
    this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  factory FeedOwner.fromJson(Map<String, dynamic> json) => FeedOwner(
        userId: json['user_id'] as String?,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );

  /// Best label for the author: display name, else @username, else a fallback.
  String get label =>
      (displayName != null && displayName!.isNotEmpty)
          ? displayName!
          : (username != null ? '@$username' : '?');
}

class FeedItem {
  final Itinerary itinerary;
  final FeedOwner owner;

  /// The title already translated into the language the feed was asked in —
  /// present only when one is cached and the title is not in that language.
  final TitleTranslation? titleTranslation;

  const FeedItem({
    required this.itinerary,
    required this.owner,
    this.titleTranslation,
  });

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        // The feed payload carries the full summary fields at the top level.
        itinerary: Itinerary.fromJson(json),
        owner: FeedOwner.fromJson(
            (json['owner'] as Map<String, dynamic>?) ?? const {}),
        titleTranslation: TitleTranslation.fromJson(
            json['title_translation'] as Map<String, dynamic>?),
      );
}
