// features/profile/presentation/user_profile_screen.dart — Another user's profile.
//
// Read-only profile view with:
//   - Avatar, display name, username, bio, follower/following counts.
//   - FollowButton widget for follow/unfollow/cancel actions.
//   - "This account is private" message if the account is private AND
//     the current user is not an accepted follower.
//   - Visible itineraries section below the profile header.
//
// Uses CustomScrollView + SliverToBoxAdapter (header) + SliverList (itineraries)
// so the entire page scrolls together without a nested scroll conflict.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/follow_button.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class UserProfileScreen extends ConsumerWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: profileAsync.when(
          data: (user) => Text(user.handle),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Profile'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (user) => _ProfileBody(userId: userId, user: user),
      ),
    ),),);
  }
}

class _ProfileBody extends ConsumerWidget {
  final String userId;
  final User user;

  const _ProfileBody({required this.userId, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isContentHidden = user.isPrivate && !user.isFollowing;
    final itinerariesAsync = ref.watch(userItinerariesProvider(userId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(userProfileProvider(userId).notifier).refresh();
        ref.read(userItinerariesProvider(userId).notifier).refresh();
      },
      child: CustomScrollView(
        slivers: [
          // ----------------------------------------------------------------
          // Profile header
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Center(
                    child: Column(
                      children: [
                        UserAvatar(avatarUrl: user.avatarUrl, radius: 48),
                        const SizedBox(height: 12),
                        Text(
                          user.nameForDisplay,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user.handle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.grey),
                            ),
                            if (user.isPrivate) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.lock,
                                  size: 14, color: Colors.grey.shade600),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Follow counts
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatBox(
                        label: 'Followers',
                        count: user.followersCount,
                        onTap: () =>
                            context.push('/profile/${user.id}/followers'),
                      ),
                      const SizedBox(width: 40),
                      _StatBox(
                        label: 'Following',
                        count: user.followingCount,
                        onTap: () =>
                            context.push('/profile/${user.id}/following'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Follow button
                  Center(
                    child: FollowButton(
                      targetUserId: user.id,
                      targetUsername: user.username,
                      isFollowing: user.isFollowing,
                      followIsPending: user.followIsPending,
                      onChanged: ({
                        required isFollowing,
                        required followIsPending,
                      }) {
                        ref
                            .read(userProfileProvider(userId).notifier)
                            .updateFollowState(
                              isFollowing: isFollowing,
                              followIsPending: followIsPending,
                            );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bio or private account message
                  if (isContentHidden) ...[
                    const Divider(),
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        Icon(Icons.lock,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'This account is private',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Follow ${user.handle} to see their posts.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ] else if (user.bio != null && user.bio!.isNotEmpty) ...[
                    Text(
                      user.bio!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],

                  // Itineraries section header (only when content is visible)
                  if (!isContentHidden) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Itineraries',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ----------------------------------------------------------------
          // Itinerary cards — only shown when content is not hidden
          // ----------------------------------------------------------------
          if (!isContentHidden)
            itinerariesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Could not load itineraries.')),
                ),
              ),
              data: (itineraries) {
                if (itineraries.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      child: Text(
                        'No public itineraries yet.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ItinerarySummaryCard(
                        itinerary: itineraries[index],
                      ),
                      childCount: itineraries.length,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Displays a single statistic (count + label) on the profile screen.
///
/// [onTap] is optional — when provided, wraps the widget in a GestureDetector
/// so the user can tap it to navigate to the followers / following list.
class _StatBox extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback? onTap;

  const _StatBox({required this.label, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            count.toString(),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
