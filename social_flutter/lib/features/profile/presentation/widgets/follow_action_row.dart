import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/follow_button.dart';

typedef FollowStateChanged = void Function({
  required bool isFollowing,
  required bool followIsPending,
});

class FollowActionRow extends StatelessWidget {
  final User user;
  final FollowStateChanged onChanged;

  const FollowActionRow({
    super.key,
    required this.user,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: FollowButton(
              targetUserId: user.id,
              targetUsername: user.username,
              isFollowing: user.isFollowing,
              followIsPending: user.followIsPending,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Decorative message button placeholder — not yet wired to a route.
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            border: Border.all(color: kBorder, width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.mail_outline_rounded,
              size: 20, color: kBark),
        ),
      ],
    );
  }
}
