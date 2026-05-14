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
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

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
      backgroundColor: kSurface,
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
                  unselectedLabelColor: kText2,
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  dividerColor: kBorder,
                  tabs: [
                    Tab(text: AppLocalizations.of(context)!.followersTabLabel(followerCount)),
                    Tab(text: AppLocalizations.of(context)!.followingTabLabel(followingCount)),
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
            SectionLabel(
              icon: Icons.hourglass_empty_rounded,
              label: AppLocalizations.of(context)!.followRequestsSectionLabel(pendingRequests.length),
              color: kAmber,
            ),
            SectionCard(
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
            SectionLabel(
              icon: Icons.group_rounded,
              label: AppLocalizations.of(context)!.allFollowersSection,
            ),
            SectionCard(
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
            _EmptyListPlaceholder(
              message: AppLocalizations.of(context)!.noFollowersYet,
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
          return _EmptyListPlaceholder(
            message: AppLocalizations.of(context)!.notFollowingAnyone,
            icon: Icons.person_add_outlined,
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            SectionLabel(
              icon: Icons.person_rounded,
              label: AppLocalizations.of(context)!.peopleYouFollow,
            ),
            SectionCard(
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
                AvatarInitials(
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
                                size: 13, color: kText3),
                          ],
                        ],
                      ),
                      Text(
                        '@${user.username}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: kText2,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: kText3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 70),
              color: kBorder),
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
              AvatarInitials(
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
                          color: kText2,
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
                        key: Key('confirmRequest_${widget.request.followId}'),
                        label: AppLocalizations.of(context)!.confirmButton,
                        filled: true,
                        onTap: _accept),
                    const SizedBox(width: 6),
                    _ActionPill(
                      key: Key('declineRequest_${widget.request.followId}'),
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
              color: kBorder),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Small building blocks
// ═══════════════════════════════════════════════════════════════════════════

class _ActionPill extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionPill({
    super.key,
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
              : Border.all(color: kBorder, width: 1.5),
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
              size: 48, color: kText3),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(color: kText2),
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
          Icon(icon, size: 48, color: kText3),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(color: kText2)),
        ],
      ),
    );
  }
}
