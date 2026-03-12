// shared/widgets/user_avatar.dart — Reusable circular avatar widget.
//
// Shows the user's avatar image if avatarUrl is provided.
// Falls back to a person icon placeholder if null or on load error.
// Used in profile screens, search results, and follow request lists.

import 'package:flutter/material.dart';

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
      backgroundImage: NetworkImage(avatarUrl!),
      // Show placeholder on network image load error.
      onBackgroundImageError: (exception, stackTrace) {},
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: null,
    );
  }
}
