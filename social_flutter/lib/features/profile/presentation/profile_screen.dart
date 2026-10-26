// features/profile/presentation/profile_screen.dart
//
// Single editorial profile screen. When [userId] is null, renders the current
// signed-in user's profile (with edit + settings + follow-requests banner);
// otherwise renders another user's profile (with the follow action row and
// the locked-content card for private accounts the viewer doesn't follow).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_error_codes.dart';
import 'package:ntripi/core/router/navigation_ext.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/core/ui/destructive_actions.dart';
import 'package:ntripi/core/utils/platform_utils.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/features/feed/providers/feed_providers.dart';
import 'package:ntripi/features/follows/presentation/follow_actions.dart';
import 'package:ntripi/features/follows/providers/follow_provider.dart';
import 'package:ntripi/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/share_link_action.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/profile/domain/visited_location.dart';
import 'package:ntripi/features/profile/presentation/fullscreen_locations_map_screen.dart';
import 'package:ntripi/features/profile/presentation/profile_identity_facts.dart';
import 'package:ntripi/features/profile/presentation/widgets/empty_itineraries_card.dart';
import 'package:ntripi/features/profile/presentation/widgets/follow_action_row.dart';
import 'package:ntripi/features/profile/presentation/widgets/follow_requests_banner.dart';
import 'package:ntripi/features/profile/presentation/widgets/verify_email_banner.dart';
import 'package:ntripi/features/profile/presentation/widgets/locked_profile_card.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_chrome.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_edit_form.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_settings_sheet.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_unavailable_view.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/features/profile/providers/user_locations_provider.dart';
import 'package:ntripi/features/reports/domain/report_target.dart';
import 'package:ntripi/features/reports/presentation/ugc_actions.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/appeal_sheet.dart';
import 'package:ntripi/shared/widgets/field_help.dart';
import 'package:ntripi/shared/widgets/fullscreen_image_viewer.dart';
import 'package:ntripi/shared/widgets/loaders.dart';
import 'package:ntripi/shared/widgets/moderation_hidden_banner.dart';
import 'package:ntripi/shared/widgets/reload_report.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  /// null ⇒ self (signed-in user); non-null ⇒ another user.
  final String? userId;

  /// Callers inside a shell branch pass their scoped base (e.g. '/search/profile')
  /// so followers/following push within the same branch navigator.
  final String profileBaseRoute;

  const ProfileScreen({
    super.key,
    this.userId,
    this.profileBaseRoute = '/profile',
  });

  bool get isSelf => userId == null;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  // Anchor for the "add a profile photo" hint that points at the Edit pencil.
  final GlobalKey _editButtonKey = GlobalKey();
  // On the Share button, which the share popup points at.
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.isSelf) {
      // Self-only: surface pending follow requests banner on first build. Nobody
      // asked for this reload, so a failure stays silent.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(ref.read(followRequestsProvider.notifier).refresh());
      });
    }
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.logoutConfirmTitle,
      message: l10n.logoutConfirmMessage,
      confirmLabel: l10n.logoutConfirmButton,
      cancelLabel: l10n.cancel,
      icon: Icons.logout,
    );
    if (!confirmed) return;
    await ref.read(authNotifierProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  /// The way out of someone else's profile, in every state. A notification can
  /// open this screen as the only route, where a plain pop has nothing to pop.
  void _leave() => context.popOr('/profile/me');

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final profileAsync = widget.isSelf
        ? ref.watch(myProfileProvider)
        : ref.watch(userProfileProvider(widget.userId!));

    return Scaffold(
      backgroundColor: nt.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
          child: profileAsync.when(
            loading: () => const Center(child: NTripiCompassLoader()),
            // A 404 means the account is gone — deleted, banned, or blocked in
            // either direction. Retrying can never change that, so it gets its
            // own screen instead of the generic message + Retry.
            error: (error, _) => isGoneError(error)
                ? ProfileUnavailableView(
                    onBack: widget.isSelf ? null : _leave,
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            extractErrorMessage(
                                error, AppLocalizations.of(context)!),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => widget.isSelf
                                ? reportReloads(context, [
                                    ref
                                        .read(myProfileProvider.notifier)
                                        .refresh(),
                                  ])
                                : ref.invalidate(
                                    userProfileProvider(widget.userId!)),
                            child: Text(AppLocalizations.of(context)!.retry),
                          ),
                          // The hero's back arrow is never built on this branch.
                          if (!widget.isSelf) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _leave,
                              child: Text(AppLocalizations.of(context)!.goBack),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
            data: (user) => widget.isSelf && _isEditing
                ? ProfileEditForm(
                    user: user,
                    onCancel: () => setState(() => _isEditing = false),
                    onSaved: () => setState(() => _isEditing = false),
                    onDeleteAccount: () =>
                        context.push('/settings/delete-account'),
                  )
                : _buildProfileView(user),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileView(User user) {
    final l10n = AppLocalizations.of(context)!;
    final isContentHidden =
        !widget.isSelf && user.isPrivate && !user.isFollowing;
    final itinerariesAsync = widget.isSelf
        ? ref.watch(myItinerariesProvider)
        : ref.watch(userItinerariesProvider(widget.userId!));
    final pendingCount = widget.isSelf
        ? (ref.watch(followRequestsProvider).value?.length ?? 0)
        : 0;
    final totalStops = isContentHidden
        ? 0
        : (itinerariesAsync.value
                ?.fold<int>(0, (s, it) => s + it.stopsCount) ??
            0);

    // Lazy fetch: cover image wins on the hero, so users with a cover never
    // trigger the locations call. Locked private profiles never fetch either.
    final shouldFetchLocations =
        user.coverImageUrl == null && !isContentHidden;
    final List<VisitedLocation> heroLocations = shouldFetchLocations
        ? (ref.watch(userLocationsProvider(user.id)).value ??
            const <VisitedLocation>[])
        : const <VisitedLocation>[];

    return RefreshIndicator(
      // Awaited: fired and forgotten, the spinner vanished at once while the
      // data was still on its way.
      onRefresh: () => reportReloads(context, [
        if (widget.isSelf) ...[
          ref.read(myProfileProvider.notifier).refresh(),
          ref.read(myItinerariesProvider.notifier).refresh(),
          ref.read(followRequestsProvider.notifier).refresh(),
        ] else ...[
          ref.read(userProfileProvider(widget.userId!).notifier).refresh(),
          ref.read(userItinerariesProvider(widget.userId!).notifier).refresh(),
        ],
        if (user.coverImageUrl == null)
          ref.read(userLocationsProvider(user.id).notifier).refresh(),
      ]),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileHeroAndIdentity(
                  user: user,
                  totalStops: totalStops,
                  isSelf: widget.isSelf,
                  isContentHidden: isContentHidden,
                  headerLabel:
                      widget.isSelf ? null : l10n.whereTheyveBeen,
                  onEdit: widget.isSelf
                      ? () => setState(() => _isEditing = true)
                      : null,
                  onSettings: widget.isSelf
                      ? () => showProfileSettingsSheet(
                            context,
                            onLogout: _logout,
                          )
                      : null,
                  notificationsAction:
                      widget.isSelf ? const NotificationBell() : null,
                  coverImageUrl: user.coverImageUrl,
                  // Every UGC surface needs a report action; a profile is one.
                  moreActions: widget.isSelf
                      ? null
                      : UgcActionsMenu(
                          target: ReportTarget.user(user.id),
                          authorUserId: user.id,
                          authorUsername: user.username,
                          onBlocked: () {
                            // My counts came back with the block itself
                            // (confirmAndBlock adopts them); the feed changed
                            // in a way no answer carries.
                            ref.invalidate(feedProvider);
                            // The profile is about to be invisible to us.
                            Navigator.of(context).maybePop();
                          },
                          onUnblocked: () {
                            // Their content is visible again, so the feed and
                            // this profile are both stale.
                            ref.invalidate(feedProvider);
                            ref.invalidate(
                                userProfileProvider(widget.userId!));
                          },
                          onRemoveFollower: user.followsYou
                              ? () => confirmAndRemoveFollower(
                                    context,
                                    ref,
                                    userId: user.id,
                                    username: user.username,
                                  )
                              : null,
                          // Wear the hero's frosted glass like Back and Share.
                          child: const GlassIconChrome(icon: Icons.more_horiz),
                        ),
                  onShare: widget.isSelf
                      ? null
                      : () => shareLink(
                            _shareButtonKey.currentContext ?? context,
                            ref,
                            ref.read(shareServiceProvider).profileLink(user, l10n),
                          ),
                  shareButtonKey: _shareButtonKey,
                  onBack: widget.isSelf ? null : _leave,
                  locations: heroLocations,
                  editButtonKey: _editButtonKey,
                  onHeroTap: isContentHidden
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullscreenLocationsMapScreen(
                                userId: user.id,
                                userName: user.nameForDisplay,
                              ),
                            ),
                          ),
                  onAvatarTap: (pos) {
                    final avatar = user.avatarUrl;
                    if (avatar != null && avatar.isNotEmpty) {
                      showFullscreenImage(context,
                          imageUrl: avatar, sourcePosition: pos);
                    } else if (widget.isSelf) {
                      // No avatar: point the owner at the Edit pencil to add one.
                      final ctx = _editButtonKey.currentContext;
                      if (ctx != null) {
                        showFieldHelp(
                          ctx,
                          title: l10n.addProfilePhoto,
                          message: l10n.addAvatarHintMessage,
                          pointer: true,
                        );
                      }
                    }
                    // Other user with no avatar: nothing to do.
                  },
                ),

                // Tally row — my-profile style for both.
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 10, 25, 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 24), // align past avatar edge
                      Tally(
                        n: user.followersCount,
                        label: l10n.followers,
                        onTap: () => context.push(
                            '${widget.profileBaseRoute}/${user.id}/followers'),
                      ),
                      Tally(
                        n: user.followingCount,
                        label: l10n.following,
                        onTap: () => context.push(
                            '${widget.profileBaseRoute}/${user.id}/following'),
                      ),
                    ],
                  ),
                ),

                // Bio below tally — my-profile style.
                if (user.bio != null && user.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InertMarkdownBody(data: user.bio!),
                  ),

                if (!isContentHidden)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: ProfileIdentityFacts(user: user),
                  ),

                // Self-only: the profile text is hidden from everyone else.
                // moderation_status only ships on GET /users/me, so this can
                // never render on someone else's profile.
                if (widget.isSelf && user.moderationStatus.isVisibleToAuthor)
                  ModerationHiddenBanner(
                    message: l10n.hiddenProfileMessage,
                    onAppeal: () => showAppealSheet(
                      context,
                      targetType: 'user',
                      targetId: user.id,
                    ),
                  ),

                // Self-only: verify-email prompt (gates create/rate/follow).
                if (widget.isSelf && !user.emailVerified)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: VerifyEmailBanner(),
                  ),

                // Self-only follow-requests banner.
                if (widget.isSelf && user.isPrivate && pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: FollowRequestsBanner(
                      count: pendingCount,
                      onTap: () => context.push('/follow-requests'),
                    ),
                  ),

                // Other-only follow action row — shown even when locked so a
                // private profile can be followed (request sent) from here.
                if (!widget.isSelf)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: FollowActionRow(
                      user: user,
                      onChanged: ({
                        required isFollowing,
                        required followIsPending,
                        required counts,
                      }) {
                        ref
                            .read(userProfileProvider(widget.userId!)
                                .notifier)
                            .updateFollowState(
                              isFollowing: isFollowing,
                              followIsPending: followIsPending,
                              counts: counts.them,
                            );
                        adoptMyCounts(
                          ProviderScope.containerOf(context, listen: false),
                          counts.me,
                        );
                        // My Following list is a keep-alive cache of this same
                        // follow. Left stale, its Following pill would offer to
                        // unfollow someone just unfollowed here. A new row is
                        // content no answer carries; a gone one is not.
                        final myId = ref.read(myProfileProvider).value?.id;
                        if (myId == null) return;
                        final following = followingProvider(myId);
                        if (isFollowing) {
                          ref.invalidate(following);
                        } else if (ref.exists(following)) {
                          ref.read(following.notifier)
                              .removeLocally(widget.userId!);
                        }
                      },
                    ),
                  ),

                if (isContentHidden)
                  LockedProfileCard(
                    isPending: user.followIsPending,
                    handle: user.handle,
                  )
                else
                  _SectionHeader(isSelf: widget.isSelf),

                if (!isContentHidden) const SizedBox(height: 10),
              ],
            ),
          ),

          if (!isContentHidden) _ItinerariesSliver(
            itinerariesAsync: itinerariesAsync,
            isSelf: widget.isSelf,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final bool isSelf;
  const _SectionHeader({required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isSelf ? l10n.latestTrip : l10n.itinerariesSectionHeader,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: nt.text2,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (isSelf)
            GestureDetector(
              onTap: () => context.go('/itineraries'),
              child: Row(
                children: [
                  Text(
                    l10n.seeAll,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: nt.forest,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: nt.forest),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItinerariesSliver extends StatelessWidget {
  final AsyncValue itinerariesAsync;
  final bool isSelf;

  const _ItinerariesSliver({
    required this.itinerariesAsync,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return itinerariesAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: NTripiSkeleton()),
        ),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(l10n.couldNotLoadItineraries)),
        ),
      ),
      data: (itineraries) {
        if (itineraries.isEmpty) {
    final nt = context.nt;
          if (isSelf) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: EmptyItinerariesCard(
                  onCreateTap: () => context.push('/itineraries/new'),
                  onExploreTap: () => context.go('/feed'),
                ),
              ),
            );
          }
          return SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l10n.noPublicItinerariesYet,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: nt.text2),
              ),
            ),
          );
        }
        // Self preview: only the latest trip. Other-user: full list.
        final count = isSelf ? 1 : itineraries.length;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  ItinerarySummaryCard(itinerary: itineraries[index]),
              childCount: count,
            ),
          ),
        );
      },
    );
  }
}
