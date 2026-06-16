// shared/widgets/user_avatar.dart — Reusable circular avatar widget.
//
// Shows the user's avatar image if avatarUrl is provided.
// Falls back to a person icon placeholder if null or on load error.
// Used in profile screens, search results, and follow request lists.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:social_flutter/core/cache/image_cache.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 30,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      // Placeholder when no avatar is set.
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.person,
          size: radius,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: CachedNetworkImageProvider(
        avatarUrl!,
        cacheManager: NtripiImageCacheManager(),
      ),
      // Show placeholder on network image load error.
      onBackgroundImageError: (exception, stackTrace) {},
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: null,
    );
  }
}
