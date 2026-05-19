// features/profile/presentation/user_profile_screen.dart
//
// "Editorial" profile view for another user (Profile Redesign.html
// "Viewing another user · 4 follow states" section).
//
// Layout matches my_profile_screen's editorial style:
//   · OSM map hero with back + share glass buttons.
//   · Avatar overlapping the hero by 36 px.
//   · Bio + Followers/Following tally in one row.
//   · Follow button (4 states: follow / following / request / requested).
//   · Identity facts chips when content is visible.
//   · Itinerary cards; private-lock placeholder when hidden.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/presentation/profile_identity_facts.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/follow_button.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';


class UserProfileScreen extends ConsumerWidget {
  final String userId;
  // Callers inside a shell branch pass their scoped base (e.g. '/search/profile')
  // so followers/following push within the same branch navigator.
  final String profileBaseRoute;
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.profileBaseRoute = '/profile',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider(userId));

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
            loading: () =>
                const Center(child: NTripiCompassLoader()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(extractErrorMessage(error, AppLocalizations.of(context)!),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(userProfileProvider(userId)),
                      child: Text(AppLocalizations.of(context)!.retry),
                    ),
                  ],
                ),
              ),
            ),
            data: (user) =>
                _ProfileBody(userId: userId, user: user, profileBaseRoute: profileBaseRoute),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final String userId;
  final User user;
  final String profileBaseRoute;
  const _ProfileBody(
      {required this.userId, required this.user, required this.profileBaseRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isContentHidden = user.isPrivate && !user.isFollowing;
    final itinerariesAsync =
        ref.watch(userItinerariesProvider(userId));
    final totalStops = isContentHidden
        ? 0
        : (itinerariesAsync.valueOrNull
                ?.fold<int>(
                    0, (sum, it) => sum + it.stopsCount) ??
            0);

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(userProfileProvider(userId).notifier).refresh();
        ref
            .read(userItinerariesProvider(userId).notifier)
            .refresh();
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero + identity overlap ──────────────────────────
                _OtherHeroAndIdentity(
                  user: user,
                  totalStops: totalStops,
                  isContentHidden: isContentHidden,
                ),

                // ── Bio + social tally ───────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: user.bio != null &&
                                user.bio!.isNotEmpty
                            ? InertMarkdownBody(data: user.bio!)
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 16),
                      _Tally(
                        n: user.followersCount,
                        label: 'Followers',
                        onTap: () => context.push(
                            '$profileBaseRoute/${user.id}/followers'),
                      ),
                      const SizedBox(width: 20),
                      _Tally(
                        n: user.followingCount,
                        label: 'Following',
                        onTap: () => context.push(
                            '$profileBaseRoute/${user.id}/following'),
                      ),
                    ],
                  ),
                ),

                // ── Follow button row ────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _FollowButtonRow(
                    user: user,
                    userId: userId,
                    ref: ref,
                  ),
                ),

                // ── Identity facts (unlocked only) ───────────────────
                if (!isContentHidden)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ProfileIdentityFacts(user: user),
                  ),

                // ── Body: locked or unlocked ─────────────────────────
                if (isContentHidden)
                  _LockedContent(
                      isPending: user.followIsPending,
                      handle: user.handle)
                else ...[
                  // Itineraries section header
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Text(
                      'ITINERARIES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kText2,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),

          // ── Itinerary cards ─────────────────────────────────────────
          if (!isContentHidden)
            itinerariesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: NTripiSkeleton()),
                ),
              ),
              error: (_, __) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child:
                          Text(AppLocalizations.of(context)!.couldNotLoadItineraries)),
                ),
              ),
              data: (itineraries) {
                if (itineraries.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        'No public itineraries yet.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: kText2),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ItinerarySummaryCard(
                          itinerary: itineraries[index]),
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

// ═══════════════════════════════════════════════════════════════════════════
// Hero + identity (other-user variant)
// ═══════════════════════════════════════════════════════════════════════════

class _OtherHeroAndIdentity extends StatelessWidget {
  final User user;
  final int totalStops;
  final bool isContentHidden;

  const _OtherHeroAndIdentity({
    required this.user,
    required this.totalStops,
    required this.isContentHidden,
  });

  @override
  Widget build(BuildContext context) {
    const heroH = 260.0;
    const identityH = 92.0;
    const overlap = 36.0;
    const totalH = heroH + identityH - overlap;

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── OSM map hero ─────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH,
            child: _OtherMapHero(
              isContentHidden: isContentHidden,
              totalStops: totalStops,
            ),
          ),

          // ── Identity row ─────────────────────────────────────────
          Positioned(
            top: heroH - overlap,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _AvatarWithBadge(
                  avatarUrl: user.avatarUrl,
                  isPrivate: user.isPrivate,
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.nameForDisplay,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: kBark,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        user.handle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: kText2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherMapHero extends StatelessWidget {
  final bool isContentHidden;
  final int totalStops;

  const _OtherMapHero({
    required this.isContentHidden,
    required this.totalStops,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // OSM tiles (non-interactive)
          IgnorePointer(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(20.0, 10.0),
                initialZoom: 2.5,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.ntripi',
                  errorTileCallback: (_, __, ___) {},
                ),
              ],
            ),
          ),

          // Sand tint
          Container(color: const Color(0x30F5F2EC)),

          // Blur veil for private / content-hidden state
          if (isContentHidden)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: const Color(0x8DF5F2EC),
                alignment: Alignment.center,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xA61A2A1E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                      )
                    ],
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),

          // Gradient for chrome legibility
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.35, 0.55, 1.0],
                colors: [
                  Color(0x8C1A2A1E),
                  Color(0x001A2A1E),
                  Color(0x001A2A1E),
                  Color(0xC71A2A1E),
                ],
              ),
            ),
          ),

          // Chrome: back + share — Positioned so Row sizes to its children.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _GlassIconButton(
                      icon: Icons.arrow_back,
                      tooltip: AppLocalizations.of(context)!.back,
                      onTap: () =>
                          Navigator.of(context).maybePop(),
                    ),
                    _GlassIconButton(
                      icon: Icons.share_outlined,
                      tooltip: AppLocalizations.of(context)!.shareProfileTooltip,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom label (only when content is visible)
          if (!isContentHidden)
            Positioned(
              left: 16,
              right: 16,
              bottom: 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "WHERE THEY'VE BEEN",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalStops > 0
                            ? '$totalStops stop${totalStops == 1 ? '' : 's'}'
                            : 'No stops yet',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Follow button row
// ═══════════════════════════════════════════════════════════════════════════

class _FollowButtonRow extends StatelessWidget {
  final User user;
  final String userId;
  final WidgetRef ref;

  const _FollowButtonRow({
    required this.user,
    required this.userId,
    required this.ref,
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
        ),
        const SizedBox(width: 8),
        // Message button placeholder
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

// ═══════════════════════════════════════════════════════════════════════════
// Private / locked-content state
// ═══════════════════════════════════════════════════════════════════════════

class _LockedContent extends StatelessWidget {
  final bool isPending;
  final String handle;

  const _LockedContent(
      {required this.isPending, required this.handle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isPending
                  ? const Color(0xFFFFF0CC)
                  : const Color(0xFFD0EBDA),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPending
                  ? Icons.hourglass_empty_rounded
                  : Icons.lock_rounded,
              size: 28,
              color:
                  isPending ? const Color(0xFFA06800) : kForest,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isPending
                ? 'Request sent'
                : 'This account is private',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: kBark,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isPending
                ? 'Once they accept your request, you\'ll see their itineraries, stops and travel map.'
                : 'Follow $handle to see their itineraries, stops and travel map.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: kText2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared widgets (identical copies of the ones in my_profile_screen.dart)
// ═══════════════════════════════════════════════════════════════════════════

class _Tally extends StatelessWidget {
  final int n;
  final String label;
  final VoidCallback? onTap;

  const _Tally({required this.n, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            n.toString(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kBark,
              letterSpacing: -0.3,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: kText2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarWithBadge extends StatelessWidget {
  final String? avatarUrl;
  final bool isPrivate;

  const _AvatarWithBadge(
      {required this.avatarUrl, required this.isPrivate});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child:
              ClipOval(child: UserAvatar(avatarUrl: avatarUrl, radius: 44)),
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.9),
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(
              isPrivate
                  ? Icons.lock_rounded
                  : Icons.public_rounded,
              size: 14,
              color: kForest,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kButtonTransparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
