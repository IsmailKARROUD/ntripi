// features/follows/presentation/follow_list_screen.dart
//
// Generic screen used for both "Followers" and "Following" lists.
//
// The same screen handles both cases — the [type] parameter controls:
//   - Which provider (and therefore which API endpoint) is used.
//   - The AppBar title shown to the user.
//
// Privacy is enforced by the backend:
//   If the target account is private and the current user is not an accepted
//   follower, the API returns 403. We catch that in the error state and show
//   a "This list is private" message instead of a generic error.
//
// Navigation:
//   Tapping a row pushes /profile/:userId so the user can view that person's profile.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

/// Controls which list the screen displays.
enum FollowListType { followers, following }

class FollowListScreen extends ConsumerWidget {
  final String userId;
  final FollowListType type;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the correct provider based on the list type.
    // Riverpod will automatically trigger a rebuild when state changes
    // (loading → data, or loading → error).
    final listAsync = type == FollowListType.followers
        ? ref.watch(followersProvider(userId))
        : ref.watch(followingProvider(userId));

    final title = type == FollowListType.followers ? 'Followers' : 'Following';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        // Error state — most likely a 403 from a private account.
        // We show a friendly lock message rather than a raw error string,
        // because "403 Forbidden" is not useful to a regular user.
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text(
                'This list is private.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),

        data: (users) {
          // Empty state — the user has no followers / isn't following anyone yet.
          if (users.isEmpty) {
            return Center(
              child: Text(
                type == FollowListType.followers
                    ? 'No followers yet.'
                    : 'Not following anyone yet.',
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }

          // Populated list with pull-to-refresh support.
          return RefreshIndicator(
            onRefresh: () => type == FollowListType.followers
                ? ref.read(followersProvider(userId).notifier).refresh()
                : ref.read(followingProvider(userId).notifier).refresh(),
            child: ListView.separated(
              itemCount: users.length,
              // Thin divider between rows for visual separation.
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _UserTile(user: users[index]),
            ),
          );
        },
      ),
    ),),);
  }
}

/// A single row in the followers / following list.
/// Shows avatar, display name (or username), username, and a lock icon
/// if the account is private.
class _UserTile extends StatelessWidget {
  final FollowerListItem user;

  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: UserAvatar(avatarUrl: user.avatarUrl, radius: 22),
      title: Row(
        children: [
          // Use display name if set, otherwise fall back to @username.
          Flexible(
            child: Text(
              user.displayName ?? '@${user.username}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          // Show a small lock icon next to the name for private accounts.
          if (user.isPrivate) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock, size: 14, color: Colors.grey.shade500),
          ],
        ],
      ),
      subtitle: Text(
        '@${user.username}',
        style: const TextStyle(color: Colors.grey),
      ),
      // Tapping navigates to the user's full public profile.
      // context.push() keeps the current screen in the back stack
      // so the user can press the back button to return to the list.
      onTap: () => context.push('/profile/${user.id}'),
    );
  }
}
