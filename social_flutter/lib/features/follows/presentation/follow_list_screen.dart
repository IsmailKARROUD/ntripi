// features/follows/presentation/follow_list_screen.dart
//
// Tabbed Followers / Following screen — Editorial redesign.
// Opens on the Followers tab when type == FollowListType.followers,
// and on the Following tab otherwise.
//
// Followers tab:
//   · "FOLLOW REQUESTS" section (only on own profile, when requests exist)
//     with Confirm / Decline inline action buttons.
//   · "ALL FOLLOWERS" section.
//
// Following tab:
//   · "PEOPLE YOU FOLLOW" section.
//
// Both sections use card-grouped rows with avatar-initials fallback.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/follow.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

const _text2 = Color(0xFF5A7562);
const _text3 = Color(0xFF93A898);
const _border = Color(0xFFE4EDE6);
const _surface = Colors.white;

enum FollowListType { followers, following }

class FollowListScreen extends ConsumerStatefulWidget {
  final String userId;
  final FollowListType type;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
  });

  @override
  ConsumerState<FollowListScreen> createState() =>
      _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex:
          widget.type == FollowListType.followers ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final followersAsync =
        ref.watch(followersProvider(widget.userId));
    final followingAsync =
        ref.watch(followingProvider(widget.userId));

    // Determine if this is the current user's own list.
    final myProfile = ref.watch(myProfileProvider).valueOrNull;
    final isOwnProfile = myProfile?.id == widget.userId;

    // Pending requests — only relevant when viewing own profile.
    final pendingRequests = isOwnProfile
        ? ref.watch(followRequestsProvider).valueOrNull ?? []
        : <FollowRequestItem>[];

    // Counts for tab labels — use loaded-list length as best proxy.
    final followerCount =
        followersAsync.valueOrNull?.length ?? 0;
    final followingCount =
        followingAsync.valueOrNull?.length ?? 0;

    // Handle for the top-bar title.
    final handle = isOwnProfile
        ? (myProfile?.handle ?? '')
        : ref
                .watch(userProfileProvider(widget.userId))
                .valueOrNull
                ?.handle ??
            '';

    return Scaffold(
      backgroundColor: kSand,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
          child: Column(
            children: [
              // ── Top bar ───────────────────────────────────────────
              SafeArea(
                bottom: false,
                child: _TopBar(handle: handle),
              ),

              // ── Tab bar ───────────────────────────────────────────
              Container(
                color: kSand,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: kForest,
                  indicatorWeight: 2.5,
                  labelColor: kForest,
                  unselectedLabelColor: _text2,
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  dividerColor: _border,
                  tabs: [
                    Tab(
                        text: followerCount > 0
                            ? '$followerCount Followers'
                            : 'Followers'),
                    Tab(
                        text: followingCount > 0
                            ? '$followingCount Following'
                            : 'Following'),
                  ],
                ),
              ),

              // ── Tab content ───────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Followers
                    RefreshIndicator(
                      onRefresh: () async {
                        ref
                            .read(followersProvider(widget.userId)
                                .notifier)
                            .refresh();
                        if (isOwnProfile) {
                          ref
                              .read(followRequestsProvider.notifier)
                              .refresh();
                        }
                      },
                      child: _FollowersTab(
                        followersAsync: followersAsync,
                        pendingRequests: pendingRequests,
                        isOwnProfile: isOwnProfile,
                        onUserTap: (id) =>
                            context.push('/profile/$id'),
                      ),
                    ),
                    // Following
                    RefreshIndicator(
                      onRefresh: () => ref
                          .read(followingProvider(widget.userId)
                              .notifier)
                          .refresh(),
                      child: _FollowingTab(
                        followingAsync: followingAsync,
                        onUserTap: (id) =>
                            context.push('/profile/$id'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Top bar
// ═══════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final String handle;
  const _TopBar({required this.handle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            color: kBark,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              handle.isNotEmpty ? handle : '',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kBark,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const IconButton(
            icon: Icon(Icons.search_rounded),
            color: kBark,
            onPressed: null,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Followers tab
// ═══════════════════════════════════════════════════════════════════════════

class _FollowersTab extends ConsumerWidget {
  final AsyncValue<List<FollowerListItem>> followersAsync;
  final List<FollowRequestItem> pendingRequests;
  final bool isOwnProfile;
  final ValueChanged<String> onUserTap;

  const _FollowersTab({
    required this.followersAsync,
    required this.pendingRequests,
    required this.isOwnProfile,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return followersAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (error, _) => _PrivateListPlaceholder(
          message: extractErrorMessage(error)),
      data: (followers) => ListView(
        padding:
            const EdgeInsets.only(bottom: 80),
        children: [
          // Pending requests (own profile only)
          if (isOwnProfile && pendingRequests.isNotEmpty) ...[
            _SectionLabel(
              icon: Icons.hourglass_empty_rounded,
              label: 'Follow requests · ${pendingRequests.length}',
              color: kAmber,
            ),
            _SectionCard(
              children: [
                for (var i = 0; i < pendingRequests.length; i++)
                  _PendingRequestRow(
                    request: pendingRequests[i],
                    isLast: i == pendingRequests.length - 1,
                  ),
              ],
            ),
          ],

          // All followers
          if (followers.isNotEmpty) ...[
            const _SectionLabel(
              icon: Icons.group_rounded,
              label: 'All followers',
            ),
            _SectionCard(
              children: [
                for (var i = 0; i < followers.length; i++)
                  _UserRow(
                    user: followers[i],
                    isLast: i == followers.length - 1,
                    onTap: () => onUserTap(followers[i].id),
                  ),
              ],
            ),
          ] else if (pendingRequests.isEmpty)
            const _EmptyListPlaceholder(
              message: 'No followers yet.',
              icon: Icons.group_outlined,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Following tab
// ═══════════════════════════════════════════════════════════════════════════

class _FollowingTab extends StatelessWidget {
  final AsyncValue<List<FollowerListItem>> followingAsync;
  final ValueChanged<String> onUserTap;

  const _FollowingTab({
    required this.followingAsync,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return followingAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (error, _) => _PrivateListPlaceholder(
          message: extractErrorMessage(error)),
      data: (following) {
        if (following.isEmpty) {
          return const _EmptyListPlaceholder(
            message: 'Not following anyone yet.',
            icon: Icons.person_add_outlined,
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            const _SectionLabel(
              icon: Icons.person_rounded,
              label: 'People you follow',
            ),
            _SectionCard(
              children: [
                for (var i = 0; i < following.length; i++)
                  _UserRow(
                    user: following[i],
                    isLast: i == following.length - 1,
                    onTap: () => onUserTap(following[i].id),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Row widgets
// ═══════════════════════════════════════════════════════════════════════════

class _UserRow extends StatelessWidget {
  final FollowerListItem user;
  final bool isLast;
  final VoidCallback onTap;

  const _UserRow({
    required this.user,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.displayName ?? '@${user.username}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _AvatarInitials(
                    name: displayName, avatarUrl: user.avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kBark,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          if (user.isPrivate) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.lock_rounded,
                                size: 13, color: _text3),
                          ],
                        ],
                      ),
                      Text(
                        '@${user.username}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: _text2,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: _text3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 70),
              color: _border),
      ],
    );
  }
}

// Pending follow-request row — Confirm + Decline buttons inline.
class _PendingRequestRow extends ConsumerStatefulWidget {
  final FollowRequestItem request;
  final bool isLast;

  const _PendingRequestRow(
      {required this.request, required this.isLast});

  @override
  ConsumerState<_PendingRequestRow> createState() =>
      _PendingRequestRowState();
}

class _PendingRequestRowState
    extends ConsumerState<_PendingRequestRow> {
  bool _loading = false;

  Future<void> _accept() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(followRequestsProvider.notifier)
          .acceptRequest(widget.request.followId);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(followRequestsProvider.notifier)
          .rejectRequest(widget.request.followId);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final displayName = r.displayName ?? '@${r.username}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _AvatarInitials(
                  name: displayName, avatarUrl: r.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kBark,
                        letterSpacing: -0.1,
                      ),
                    ),
                    Text(
                      '@${r.username}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: _text2,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionPill(
                        label: 'Confirm',
                        filled: true,
                        onTap: _accept),
                    const SizedBox(width: 6),
                    _ActionPill(
                      icon: Icons.close_rounded,
                      filled: false,
                      onTap: _decline,
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (!widget.isLast)
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 70),
              color: _border),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Small building blocks
// ═══════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel({
    required this.icon,
    required this.label,
    this.color = _text2,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionPill({
    this.label,
    this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: filled ? kForest : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled
              ? null
              : Border.all(color: _border, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon,
                  size: 16,
                  color: filled ? Colors.white : kBark),
            if (label != null)
              Text(
                label!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : kBark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Avatar with initials fallback — shows the first letter(s) of the name
// on a color-coded background when no photo is available.
class _AvatarInitials extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  static const _size = 44.0;

  const _AvatarInitials({required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return UserAvatar(avatarUrl: avatarUrl, radius: _size / 2);
    }
    final initials = _initials(name);
    final palette = _palette(name);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: palette.$1,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: _size * 0.38,
          fontWeight: FontWeight.w700,
          color: palette.$2,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static (Color, Color) _palette(String name) {
    const palettes = [
      (Color(0xFFD0EBDA), Color(0xFF1F5E3A)),
      (Color(0xFFFFE3CC), Color(0xFFA05D1F)),
      (Color(0xFFE0DAF0), Color(0xFF5A3F8F)),
      (Color(0xFFF4D4A8), Color(0xFF8A3A1F)),
      (Color(0xFFCDE0D6), Color(0xFF3B6EA5)),
    ];
    int h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return palettes[h % palettes.length];
  }
}

// Error / private-list placeholder.
class _PrivateListPlaceholder extends StatelessWidget {
  final String message;
  const _PrivateListPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 48, color: _text3),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(color: _text2),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// Empty state.
class _EmptyListPlaceholder extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyListPlaceholder(
      {required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _text3),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(color: _text2)),
        ],
      ),
    );
  }
}
