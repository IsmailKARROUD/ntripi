// features/profile/presentation/my_profile_screen.dart — Own profile screen.
//
// Shows the current user's profile with:
//   - Avatar, display name, username, bio, follower/following counts.
//   - Inline edit mode (toggled by an icon, no separate screen needed).
//   - Privacy toggle (public/private account switch).
//   - "Follow Requests (N)" banner if private and there are pending requests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  bool _isEditing = false;
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  bool? _editIsPrivate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(followRequestsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  void _startEditing(User user) {
    _displayNameController.text = user.displayName ?? '';
    _bioController.text = user.bio ?? '';
    _avatarUrlController.text = user.avatarUrl ?? '';
    _editIsPrivate = user.isPrivate;
    setState(() => _isEditing = true);
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () {
                Navigator.pop(ctx);
                _logout();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete Account',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/settings/delete-account');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    // Ask for confirmation before logging out.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Delete the stored token and clear auth state.
    await ref.read(authNotifierProvider.notifier).logout();

    // Replace the entire navigation stack with the login screen.
    if (mounted) context.go('/login');
  }

  Future<void> _saveEdits() async {
    final avatarText = _avatarUrlController.text.trim();
    await ref.read(myProfileProvider.notifier).updateProfile(
          displayName: _displayNameController.text.trim().isEmpty
              ? null
              : _displayNameController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
          avatarUrl: avatarText.isEmpty ? null : avatarText,
          clearAvatarUrl: avatarText.isEmpty,
          isPrivate: _editIsPrivate,
        );
    if (mounted) {
      setState(() => _isEditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final followRequestsAsync = ref.watch(followRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          profileAsync.when(
            data: (user) => IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit_outlined),
              tooltip: _isEditing ? 'Cancel editing' : 'Edit profile',
              onPressed: () {
                if (_isEditing) {
                  setState(() => _isEditing = false);
                } else {
                  _startEditing(user);
                }
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // Settings button — opens logout / delete account sheet.
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
    body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  extractErrorMessage(error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.read(myProfileProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (user) => _isEditing
            ? _buildEditForm(user)
            : _buildProfileView(user, followRequestsAsync),
      ),
    ),),);
  }

  Widget _buildProfileView(User user, AsyncValue followRequestsAsync) {
    final pendingCount = followRequestsAsync.valueOrNull?.length ?? 0;
    final itinerariesAsync = ref.watch(myItinerariesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(myProfileProvider.notifier).refresh();
        ref.read(myItinerariesProvider.notifier).refresh();
        ref.read(followRequestsProvider.notifier).refresh();
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
                  // Avatar + display name
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
                        Text(
                          user.handle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey),
                        ),
                        if (user.isPrivate) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'Private account',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Follow counts — tappable to open the full list.
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

                  // Bio
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    Text(
                      user.bio!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Follow requests banner
                  if (user.isPrivate && pendingCount > 0) ...[
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.person_add),
                        title: Text('Follow Requests ($pendingCount)'),
                        subtitle: const Text('Tap to review'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/follow-requests'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Itineraries section header
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Itineraries',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/itineraries'),
                          child: const Text('See all'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ----------------------------------------------------------------
          // Itinerary cards
          // ----------------------------------------------------------------
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        Icon(Icons.map_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text('No itineraries yet.'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push('/itineraries/new'),
                          child: const Text('Create your first trip'),
                        ),
                      ],
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

  Widget _buildEditForm(User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: UserAvatar(avatarUrl: user.avatarUrl, radius: 48)),
          const SizedBox(height: 24),

          TextFormField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              label: LabelWithHelp(
                label: 'Display Name',
                helpTitle: 'Display name',
                helpMessage:
                    'How your name appears on your profile and posts. Up to 50 characters; supports emoji.',
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _bioController,
            maxLines: 3,
            decoration: const InputDecoration(
              label: LabelWithHelp(
                label: 'Bio',
                helpTitle: 'Bio',
                helpMessage:
                    'A short description shown on your profile. A few hundred characters max; supports emoji.',
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _avatarUrlController,
            decoration: const InputDecoration(
              label: LabelWithHelp(
                label: 'Avatar URL',
                helpTitle: 'Avatar URL',
                helpMessage:
                    'Direct link to an image hosted online. Leave blank to keep your current avatar.',
              ),
              border: OutlineInputBorder(),
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 16),

          // Privacy toggle
          SwitchListTile(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Private Account'),
                SizedBox(width: 2),
                FieldHelpIcon(
                  helpTitle: 'Private account',
                  helpMessage:
                      'When private, people must request to follow you before they can see your itineraries. Switching back to public auto-accepts every pending request.',
                ),
              ],
            ),
            subtitle: const Text(
                'When private, people must request to follow you.'),
            value: _editIsPrivate ?? user.isPrivate,
            onChanged: (value) {
              setState(() => _editIsPrivate = value);
            },
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: _saveEdits,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

/// Displays a single statistic (count + label) on the profile screen.
///
/// [onTap] is optional — when provided, the whole widget becomes tappable
/// (wrapped in a GestureDetector). This is used to navigate to the
/// followers / following list when the user taps the count.
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
