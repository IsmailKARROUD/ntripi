// features/profile/presentation/profile_screen.dart
//
// Single editorial profile screen. When [userId] is null, renders the current
// signed-in user's profile (with edit + settings + follow-requests banner);
// otherwise renders another user's profile (with the follow action row and
// the locked-content card for private accounts the viewer doesn't follow).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
import 'package:social_flutter/features/profile/presentation/fullscreen_locations_map_screen.dart';
import 'package:social_flutter/features/profile/presentation/profile_identity_facts.dart';
import 'package:social_flutter/features/profile/presentation/widgets/empty_itineraries_card.dart';
import 'package:social_flutter/features/profile/presentation/widgets/follow_action_row.dart';
import 'package:social_flutter/features/profile/presentation/widgets/follow_requests_banner.dart';
import 'package:social_flutter/features/profile/presentation/widgets/locked_profile_card.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_chrome.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_edit_form.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_settings_sheet.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/profile/providers/user_locations_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.isSelf) {
      // Self-only: surface pending follow requests banner on first build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(followRequestsProvider.notifier).refresh();
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = widget.isSelf
        ? ref.watch(myProfileProvider)
        : ref.watch(userProfileProvider(widget.userId!));

    return Scaffold(
      backgroundColor: kSurface,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
          child: profileAsync.when(
            loading: () => const Center(child: NTripiCompassLoader()),
            error: (error, _) => Center(
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
                          ? ref.read(myProfileProvider.notifier).refresh()
                          : ref.invalidate(
                              userProfileProvider(widget.userId!)),
                      child: Text(AppLocalizations.of(context)!.retry),
                    ),
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
        ? (ref.watch(followRequestsProvider).valueOrNull?.length ?? 0)
        : 0;
    final totalStops = isContentHidden
        ? 0
        : (itinerariesAsync.valueOrNull
                ?.fold<int>(0, (s, it) => s + it.stopsCount) ??
            0);

    // Lazy fetch: cover image wins on the hero, so users with a cover never
    // trigger the locations call. Locked private profiles never fetch either.
    final shouldFetchLocations =
        user.coverImageUrl == null && !isContentHidden;
    final List<VisitedLocation> heroLocations = shouldFetchLocations
        ? (ref.watch(userLocationsProvider(user.id)).valueOrNull ??
            const <VisitedLocation>[])
        : const <VisitedLocation>[];

    return RefreshIndicator(
      onRefresh: () async {
        if (widget.isSelf) {
          ref.read(myProfileProvider.notifier).refresh();
          ref.read(myItinerariesProvider.notifier).refresh();
          ref.read(followRequestsProvider.notifier).refresh();
        } else {
          ref.read(userProfileProvider(widget.userId!).notifier).refresh();
          ref.read(userItinerariesProvider(widget.userId!).notifier).refresh();
        }
        if (user.coverImageUrl == null) {
          ref.read(userLocationsProvider(user.id).notifier).refresh();
        }
      },
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
                  coverImageUrl: user.coverImageUrl,
                  locations: heroLocations,
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

                // Self-only follow-requests banner.
                if (widget.isSelf && user.isPrivate && pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: FollowRequestsBanner(
                      count: pendingCount,
                      onTap: () => context.push('/follow-requests'),
                    ),
                  ),

                // Other-only follow action row.
                if (!widget.isSelf && !isContentHidden)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: FollowActionRow(
                      user: user,
                      onChanged: ({
                        required isFollowing,
                        required followIsPending,
                      }) {
                        ref
                            .read(userProfileProvider(widget.userId!)
                                .notifier)
                            .updateFollowState(
                              isFollowing: isFollowing,
                              followIsPending: followIsPending,
                            );
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
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isSelf ? l10n.latestTrip : l10n.itinerariesSectionHeader,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kText2,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kForest,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: kForest),
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
                    ?.copyWith(color: kText2),
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
