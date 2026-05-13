// features/profile/presentation/my_profile_screen.dart
//
// "Editorial" profile redesign (Profile Redesign.html).
// Layout (top → bottom):
//   · Full-bleed OSM map hero (260 px) with gradient + glass Edit/Settings
//     buttons. Avatar overlaps the hero bottom edge by 36 px.
//   · Identity row: avatar + display-name + @handle.
//   · Bio + Followers/Following tally in one horizontal row.
//   · Optional follow-requests banner (private accounts).
//   · "LATEST TRIP" section header + itinerary cards.
//   · Empty-state invitation card when no itineraries yet.
//
// Edit mode is an inline full-screen form: Cancel · Edit profile · Save at
// the top, grouped card sections below (Identity / Privacy).
//
// Settings is a bottom sheet with grouped rows: Account · Support ·
// Destructive (Log out / Delete account).

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

// ── Extra palette tokens used only in this screen ──────────────────────────
const _text2 = Color(0xFF5A7562);
const _text3 = Color(0xFF93A898);
const _border = Color(0xFFE4EDE6);
const _surface = Colors.white;

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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SettingsSheet(
        onLogout: () {
          Navigator.pop(ctx);
          _logout();
        },
        onDeleteAccount: () {
          Navigator.pop(ctx);
          context.push('/settings/delete-account');
        },
      ),
    );
  }

  Future<void> _logout() async {
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
    await ref.read(authNotifierProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  Future<void> _saveEdits() async {
    final currentUser = ref.read(myProfileProvider).valueOrNull;
    final pendingCount =
        ref.read(followRequestsProvider).valueOrNull?.length ?? 0;
    final switchingToPublic =
        currentUser != null && currentUser.isPrivate && _editIsPrivate == false;

    if (switchingToPublic && pendingCount > 0) {
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: 'Switch to public?',
        message: pendingCount == 1
            ? 'You have 1 pending follow request. Switching to public will '
                'automatically accept it. Continue?'
            : 'You have $pendingCount pending follow requests. Switching to '
                'public will automatically accept all of them. Continue?',
        confirmLabel: 'Switch to public',
      );
      if (!confirmed) return;
    }

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
    if (mounted) setState(() => _isEditing = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final followRequestsAsync = ref.watch(followRequestsProvider);

    return Scaffold(
      backgroundColor: _surface,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
          ),
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
        ),
      ),
    );
  }

  // ── Profile view ──────────────────────────────────────────────────────────

  Widget _buildProfileView(User user, AsyncValue followRequestsAsync) {
    final pendingCount = followRequestsAsync.valueOrNull?.length ?? 0;
    final itinerariesAsync = ref.watch(myItinerariesProvider);
    final totalStops = itinerariesAsync.valueOrNull
            ?.fold<int>(0, (sum, it) => sum + it.stopsCount) ??
        0;

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(myProfileProvider.notifier).refresh();
        ref.read(myItinerariesProvider.notifier).refresh();
        ref.read(followRequestsProvider.notifier).refresh();
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero + identity overlap ──────────────────────────────
                _HeroAndIdentity(
                  user: user,
                  totalStops: totalStops,
                  isSelf: true,
                  onEdit: () => _startEditing(user),
                  onSettings: _showSettingsSheet,
                ),

                // ── Bio + social tally ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 10, 25, 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 24), // to align with avatar edge
                      _Tally(
                        n: user.followersCount,
                        label: 'Followers',
                        onTap: () =>
                            context.push('/profile/${user.id}/followers'),
                      ),
                      _Tally(
                        n: user.followingCount,
                        label: 'Following',
                        onTap: () =>
                            context.push('/profile/${user.id}/following'),
                      ),
                    ],
                  ),
                ),
                if (user.bio != null && user.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InertMarkdownBody(data: user.bio!),
                  ),
                // ── Follow-requests banner ───────────────────────────────
                if (user.isPrivate && pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _FollowRequestsBanner(
                      count: pendingCount,
                      onTap: () => context.push('/follow-requests'),
                    ),
                  ),

                // ── "Latest trip" section header ─────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LATEST TRIP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _text2,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.go('/itineraries'),
                        child: const Row(
                          children: [
                            Text(
                              'See all',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kForest,
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 16, color: kForest),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),

          // ── Itinerary cards / empty state ──────────────────────────────
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _EmptyItinerariesCard(
                      onCreateTap: () => context.push('/itineraries/new'),
                      onExploreTap: () => context.go('/itineraries'),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        ItinerarySummaryCard(itinerary: itineraries[index]),
                    childCount: 1, //just the latest trip on the profile view
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Edit form ─────────────────────────────────────────────────────────────

  Widget _buildEditForm(User user) {
    return Column(
      children: [
        // Cancel · Edit profile · Save
        SafeArea(
          bottom: false,
          child: Container(
            color: kSand,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  style: TextButton.styleFrom(foregroundColor: _text2),
                  child: const Text('Cancel',
                      style:
                          TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                ),
                const Expanded(
                  child: Text(
                    'Edit profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kBark,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saveEdits,
                  child: const Text('Save',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),

        // Scrollable form
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Avatar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: kSand,
                              ),
                              child: UserAvatar(
                                  avatarUrl: user.avatarUrl, radius: 46),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: kForest,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kSand, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.photo_camera,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Change photo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kForest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Identity section
                const _SectionLabel(
                    icon: Icons.person_outline_rounded, label: 'Identity'),
                _SectionCard(children: [
                  _EditFieldRow(
                    icon: Icons.badge_outlined,
                    label: 'Display name',
                    child: TextField(
                      controller: _displayNameController,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kBark,
                          fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.alternate_email_rounded,
                    label: 'Username',
                    child: Text(
                      user.handle,
                      style: const TextStyle(
                          fontSize: 15,
                          color: _text2,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.notes_rounded,
                    label: 'Bio',
                    child: MarkdownNotesEditor(
                      controller: _bioController,
                      readOnly: false,
                      label: '',
                      helpTitle: 'Bio',
                      helpMessage:
                          'A short description. Supports **bold** markdown and emoji.',
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.link_rounded,
                    label: 'Avatar URL',
                    child: TextField(
                      controller: _avatarUrlController,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kBark,
                          fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: 'https://…',
                        hintStyle: TextStyle(color: _text3, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ]),

                // Privacy section
                const _SectionLabel(
                    icon: Icons.lock_outline_rounded, label: 'Privacy'),
                _SectionCard(children: [
                  _ToggleRow(
                    icon: Icons.lock_rounded,
                    label: 'Private account',
                    subtitle:
                        'People must request to follow you to see your itineraries.',
                    value: _editIsPrivate ?? user.isPrivate,
                    onChanged: (v) => setState(() => _editIsPrivate = v),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hero + Identity overlap
// ═══════════════════════════════════════════════════════════════════════════

/// Renders the OSM map hero (260 px) with the avatar + name/handle
/// row overlapping it by 36 px at the bottom. Used for both self
/// and other-user profiles via [isSelf].
class _HeroAndIdentity extends StatelessWidget {
  final User user;
  final int totalStops;
  final bool isSelf;
  final VoidCallback? onEdit;
  final VoidCallback? onSettings;
  // For other-user profile, back/share callbacks.
  const _HeroAndIdentity({
    required this.user,
    required this.totalStops,
    this.isSelf = true,
    this.onEdit,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    const heroH = 260.0;
    // Avatar total display height inside the row = 92 px (88 radius×2 + ring 4)
    // Identity row height ≈ 92 px. Overlap = 36 px.
    // Total section height = heroH + (92 − 36) = 316 px.
    const identityH = 92.0;
    const overlap = 36.0;
    const totalH = heroH + identityH - overlap;

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── OSM map tile layer ─────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH,
            child: _MapHero(
              isSelf: isSelf,
              totalStops: totalStops,
              isPrivate: user.isPrivate,
              onEdit: onEdit,
              onSettings: onSettings,
            ),
          ),

          // ── Identity row (avatar + name/handle) ───────────────────────
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
                          color: _text2,
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

// ── Map hero ─────────────────────────────────────────────────────────────

class _MapHero extends StatelessWidget {
  final bool isSelf;
  final int totalStops;
  final bool isPrivate;
  final VoidCallback? onEdit;
  final VoidCallback? onSettings;
  const _MapHero({
    required this.isSelf,
    required this.totalStops,
    required this.isPrivate,
    this.onEdit,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // OSM tile layer — non-interactive, decorative.
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
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.ntripi',
                  // Silently discard tile errors (offline / test mode).
                  errorTileCallback: (_, __, ___) {},
                ),
              ],
            ),
          ),

          // Sand tint overlay for brand warmth
          Container(
            color: const Color(0x30F5F2EC),
          ),

          // Gradient: dark top + dark bottom for chrome legibility
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.35, 0.55, 1.0],
                colors: [
                  Color(0x801A2A1E),
                  Color(0x001A2A1E),
                  Color(0x001A2A1E),
                  Color(0xC71A2A1E),
                ],
              ),
            ),
          ),

          // Chrome: buttons — Positioned so the Row sizes to its children
          // instead of stretching to the full Stack height.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: isSelf
                      ? [
                          _GlassIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit profile',
                            onTap: onEdit,
                          ),
                          _GlassIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: 'Settings',
                            onTap: onSettings,
                          ),
                        ]
                      : [
                          _GlassIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Back',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const _GlassIconButton(
                            icon: Icons.share_outlined,
                            tooltip: 'Share profile',
                          ),
                        ],
                ),
              ),
            ),
          ),
          // const Spacer(),
          // Bottom label: "WHERE I'VE BEEN · X stops"
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
                      "WHERE I'VE BEEN",
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
                const Spacer(),
                // "Expand" pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full,
                          size: 12, color: Colors.white, weight: 600),
                      SizedBox(width: 4),
                      Text(
                        'Expand',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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

// ── Avatar with privacy badge ─────────────────────────────────────────────

class _AvatarWithBadge extends StatelessWidget {
  final String? avatarUrl;
  final bool isPrivate;

  const _AvatarWithBadge({required this.avatarUrl, required this.isPrivate});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // White ring around avatar
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: ClipOval(
            child: UserAvatar(avatarUrl: avatarUrl, radius: 44),
          ),
        ),
        // Privacy badge (bottom-right)
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
              isPrivate ? Icons.lock_rounded : Icons.public_rounded,
              size: 14,
              color: kForest,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Glass icon button (overlaid on map) ──────────────────────────────────

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
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Profile-view sub-widgets
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
              color: _text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowRequestsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FollowRequestsBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD0EBDA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_add_rounded, size: 20, color: kForest),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Follow Requests ($count)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kForest,
                    ),
                  ),
                  const Text(
                    'Tap to review',
                    style: TextStyle(
                        fontSize: 12,
                        color: kForest,
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kForest, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyItinerariesCard extends StatelessWidget {
  final VoidCallback onCreateTap;
  final VoidCallback onExploreTap;

  const _EmptyItinerariesCard(
      {required this.onCreateTap, required this.onExploreTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary invitation card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFD0EBDA),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kForest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kForest.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.map_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(height: 12),
              const Text(
                'Plan your first journey',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add stops, transit segments and notes. Share it with friends or keep it private.',
                style: TextStyle(fontSize: 13, color: _text2, height: 1.5),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onCreateTap,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: kForest,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: kForest.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Create itinerary',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Secondary path — browse/explore
        GestureDetector(
          onTap: onExploreTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: const Row(
              children: [
                _SmallIconBox(icon: Icons.explore_rounded),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need inspiration?',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kBark),
                      ),
                      Text(
                        'Browse your itineraries for ideas.',
                        style: TextStyle(fontSize: 11, color: _text2),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: _text3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SmallIconBox extends StatelessWidget {
  final IconData icon;
  const _SmallIconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: kSand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: kForest),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Edit-form sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _text2),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _text2,
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
      child: Column(children: children),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
        height: 1, margin: const EdgeInsets.only(left: 16), color: _border);
  }
}

class _EditFieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _EditFieldRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFD0EBDA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: kForest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _text2,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: value ? const Color(0xFFD0EBDA) : const Color(0xFFF5F2EC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: value ? kForest : _text2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kBark)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          fontSize: 12, color: _text2, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: kForest,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Settings bottom sheet
// ═══════════════════════════════════════════════════════════════════════════

class _SettingsSheet extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const _SettingsSheet({
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _text3.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),

          // Account section
          _SheetSection(
            label: 'Account',
            children: [
              _SheetRow(
                icon: Icons.notifications_outlined,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: 'Notifications',
                detail: 'On',
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.lock_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: 'Privacy & security',
                detail: 'Private',
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.language_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: 'Language',
                detail: 'English',
                isLast: true,
                onTap: () => _comingSoon(context),
              ),
            ],
          ),

          // Support section
          _SheetSection(
            label: 'Support',
            children: [
              _SheetRow(
                icon: Icons.help_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: 'Help center',
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.info_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: 'About Ntripi',
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.gavel_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: 'Terms & Privacy',
                isLast: true,
                onTap: () => _comingSoon(context),
              ),
            ],
          ),

          // Destructive section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  _SheetRow(
                    icon: Icons.logout_rounded,
                    iconBg: const Color(0xFFD0EBDA),
                    iconColor: kForest,
                    label: 'Log out',
                    showChevron: false,
                    onTap: onLogout,
                  ),
                  Container(
                      height: 1,
                      margin: const EdgeInsets.only(left: 56),
                      color: _border),
                  _SheetRow(
                    icon: Icons.delete_outline_rounded,
                    iconBg: const Color(0xFFFFDAD6),
                    iconColor: const Color(0xFFBA1A1A),
                    label: 'Delete account',
                    labelColor: const Color(0xFFBA1A1A),
                    showChevron: false,
                    isLast: true,
                    onTap: onDeleteAccount,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _SheetSection({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _text2,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final String? detail;
  final bool showChevron;
  final bool isLast;
  final VoidCallback? onTap;

  const _SheetRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.labelColor = kBark,
    this.detail,
    this.showChevron = true,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(16))
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                ),
                if (detail != null) ...[
                  Text(detail!,
                      style: const TextStyle(fontSize: 13, color: _text2)),
                  const SizedBox(width: 4),
                ],
                if (showChevron)
                  const Icon(Icons.chevron_right, size: 20, color: _text3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 56),
              color: _border),
      ],
    );
  }
}
