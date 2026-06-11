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
import 'package:social_flutter/features/profile/presentation/country_picker_screen.dart';
import 'package:social_flutter/features/profile/presentation/language_picker_sheet.dart';
import 'package:social_flutter/features/profile/presentation/profile_identity_facts.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/data/countries.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';
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
  List<String> _editPassportCountries = [];
  bool _passportCountriesChanged = false;
  String? _editResidentCountry;
  bool _residentChanged = false;
  List<String> _editLanguages = [];
  bool _languagesChanged = false;

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
    _editPassportCountries = List.from(user.passportCountries ?? []);
    _passportCountriesChanged = false;
    _editResidentCountry = user.residentCountry;
    _residentChanged = false;
    _editLanguages = List.from(user.languages ?? []);
    _languagesChanged = false;
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutConfirmTitle),
        content: Text(l10n.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.logoutConfirmButton),
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
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: l10n.switchToPublicTitle,
        message: l10n.switchToPublicMessage(pendingCount),
        confirmLabel: l10n.switchToPublicButton,
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
          passportCountries: _editPassportCountries,
          passportCountriesChanged: _passportCountriesChanged,
          residentCountry: _editResidentCountry,
          clearResidentCountry: _residentChanged && _editResidentCountry == null,
          languages: _editLanguages,
          languagesChanged: _languagesChanged,
        );
    if (mounted) setState(() => _isEditing = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final followRequestsAsync = ref.watch(followRequestsProvider);

    return Scaffold(
      backgroundColor: kSurface,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
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
                      extractErrorMessage(error, AppLocalizations.of(context)!),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.read(myProfileProvider.notifier).refresh(),
                      child: Text(AppLocalizations.of(context)!.retry),
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
                        label: AppLocalizations.of(context)!.followers,
                        onTap: () =>
                            context.push('/profile/${user.id}/followers'),
                      ),
                      _Tally(
                        n: user.followingCount,
                        label: AppLocalizations.of(context)!.following,
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
                // ── Identity facts (passport · lives in · languages) ─────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: ProfileIdentityFacts(user: user),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.latestTrip,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kText2,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.go('/itineraries'),
                        child: Row(
                          children: [
                            Text(
                              AppLocalizations.of(context)!.seeAll,
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
                child: Center(child: NTripiSkeleton()),
              ),
            ),
            error: (_, __) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(AppLocalizations.of(context)!.couldNotLoadItineraries)),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  style: TextButton.styleFrom(foregroundColor: kText2),
                  child: Text(AppLocalizations.of(context)!.cancel,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.editProfileTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kBark,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saveEdits,
                  child: Text(AppLocalizations.of(context)!.save,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
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
                        Text(
                          AppLocalizations.of(context)!.uploadPhoto,
                          style: const TextStyle(
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
                _SectionLabel(
                    icon: Icons.person_outline_rounded, label: AppLocalizations.of(context)!.identitySection),
                _SectionCard(children: [
                  _EditFieldRow(
                    icon: Icons.badge_outlined,
                    label: AppLocalizations.of(context)!.displayNameLabel,
                    child: TextField(
                      controller: _displayNameController,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kBark,
                          fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
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
                          color: kText2,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.notes_rounded,
                    child: MarkdownNotesEditor(
                      controller: _bioController,
                      readOnly: false,
                      label: AppLocalizations.of(context)!.bioLabel,
                      helpTitle: AppLocalizations.of(context)!.bioLabel,
                      helpMessage: AppLocalizations.of(context)!.bioHelpMessage,
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.link_rounded,
                    label: AppLocalizations.of(context)!.avatarUrlLabel,
                    child: TextField(
                      controller: _avatarUrlController,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kBark,
                          fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: 'https://…',
                        hintStyle: TextStyle(color: kText3, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),

                // Travel identity section
                _SectionLabel(
                    icon: Icons.public_rounded, label: AppLocalizations.of(context)!.travelIdentitySection),
                _SectionCard(children: [
                  _CodeChipsRow(
                    icon: Icons.badge_outlined,
                    label: AppLocalizations.of(context)!.passportLabel,
                    codes: _editPassportCountries,
                    labelFor: (code) =>
                        '${countryByCode(code)?.flag ?? ''} $code'.trim(),
                    onAdd: () async {
                      final code = await Navigator.of(context).push<String?>(
                        MaterialPageRoute(
                          builder: (_) => CountryPickerScreen(
                            exclude: _editPassportCountries,
                          ),
                        ),
                      );
                      if (code != null && code.isNotEmpty && mounted) {
                        setState(() {
                          _editPassportCountries = [..._editPassportCountries, code];
                          _passportCountriesChanged = true;
                        });
                      }
                    },
                    onRemove: (code) => setState(() {
                      _editPassportCountries =
                          _editPassportCountries.where((c) => c != code).toList();
                      _passportCountriesChanged = true;
                    }),
                  ),
                  const _FieldDivider(),
                  _PickerRow(
                    icon: Icons.location_on_outlined,
                    label: AppLocalizations.of(context)!.livesInLabel,
                    countryCode: _editResidentCountry,
                    onTap: () async {
                      final code = await Navigator.of(context).push<String?>(
                        MaterialPageRoute(
                          builder: (_) => const CountryPickerScreen(allowClear: true),
                        ),
                      );
                      if (code != null && mounted) {
                        setState(() {
                          _editResidentCountry = code.isEmpty ? null : code;
                          _residentChanged = true;
                        });
                      }
                    },
                  ),
                  const _FieldDivider(),
                  _CodeChipsRow(
                    icon: Icons.translate_outlined,
                    label: AppLocalizations.of(context)!.languagesLabel,
                    codes: _editLanguages,
                    labelFor: (code) => code,
                    onAdd: () async {
                      final code = await showLanguagePickerSheet(
                        context,
                        exclude: _editLanguages,
                      );
                      if (code != null && mounted) {
                        setState(() {
                          _editLanguages = [..._editLanguages, code];
                          _languagesChanged = true;
                        });
                      }
                    },
                    onRemove: (code) => setState(() {
                      _editLanguages =
                          _editLanguages.where((c) => c != code).toList();
                      _languagesChanged = true;
                    }),
                  ),
                ]),

                // Privacy section
                _SectionLabel(
                    icon: Icons.lock_outline_rounded, label: AppLocalizations.of(context)!.privacySection),
                _SectionCard(children: [
                  _ToggleRow(
                    icon: Icons.lock_rounded,
                    label: AppLocalizations.of(context)!.privateAccountLabel,
                    subtitle: AppLocalizations.of(context)!.privateAccountSubtitle,
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
                            tooltip: AppLocalizations.of(context)!.editProfileTooltip,
                            onTap: onEdit,
                          ),
                          _GlassIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: AppLocalizations.of(context)!.settingsTooltip,
                            onTap: onSettings,
                          ),
                        ]
                      : [
                          _GlassIconButton(
                            icon: Icons.arrow_back,
                            tooltip: AppLocalizations.of(context)!.back,
                            onTap: () => Navigator.of(context).maybePop(),
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
                    Text(
                      AppLocalizations.of(context)!.whereIveBeen,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      totalStops > 0
                          ? AppLocalizations.of(context)!.stopCount(totalStops)
                          : AppLocalizations.of(context)!.noStopsYet,
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
                    color: kButtonTransparent,
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_full,
                          size: 12, color: Colors.white, weight: 600),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)!.expand,
                        style: const TextStyle(
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
                color: kButtonTransparent,
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
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
                    AppLocalizations.of(context)!.followRequestsBannerTitle(count),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kForest,
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.tapToReview,
                    style: const TextStyle(
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
            border: Border.all(color: kBorder),
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
              Text(
                AppLocalizations.of(context)!.planFirstJourney,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.planFirstJourneyHint,
                style: const TextStyle(fontSize: 13, color: kText2, height: 1.5),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)!.createItinerary,
                        style: const TextStyle(
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
              color: kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                const _SmallIconBox(icon: Icons.explore_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.needInspiration,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kBark),
                      ),
                      Text(
                        AppLocalizations.of(context)!.browseForIdeas,
                        style: const TextStyle(fontSize: 11, color: kText2),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: kText3),
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
          Icon(icon, size: 14, color: kText2),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kText2,
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
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
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
        height: 1, margin: const EdgeInsets.only(left: 16), color: kBorder);
  }
}

class _EditFieldRow extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Widget child;

  const _EditFieldRow({
    required this.icon,
    this.label,
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
            child: label != null ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                child,
              ],
            ) : child,
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
              color: value ? kForest : kText2,
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
                          fontSize: 12, color: kText2, height: 1.4)),
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

class _SettingsSheet extends ConsumerWidget {
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const _SettingsSheet({
    required this.onLogout,
    required this.onDeleteAccount,
  });

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentCode = ref.read(localeProvider).languageCode;

    final languages = [
      (code: 'en', label: l10n.languageEnglish),
      (code: 'fr', label: l10n.languageFrench),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: kSand,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.languagePickerTitle.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < languages.length; i++) ...[
                      if (i > 0)
                        Container(
                          height: 1,
                          color: kBorder,
                          margin: const EdgeInsets.only(left: 16),
                        ),
                      InkWell(
                        onTap: () {
                          ref
                              .read(localeProvider.notifier)
                              .setLocale(Locale(languages[i].code));
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: kMist,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  languages[i].code.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: kForest,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  languages[i].label,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: kBark,
                                  ),
                                ),
                              ),
                              if (currentCode == languages[i].code)
                                const Icon(Icons.check_rounded,
                                    size: 18, color: kForest),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);
    final langDetail = currentLocale.languageCode == 'fr'
        ? l10n.languageFrench
        : l10n.languageEnglish;

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
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
              color: kText3.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.settingsTitle,
                style: const TextStyle(
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
            label: l10n.settingsAccount,
            children: [
              _SheetRow(
                icon: Icons.notifications_outlined,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsNotifications,
                detail: l10n.settingsNotificationsOff,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.language_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsLanguage,
                detail: langDetail,
                isLast: true,
                onTap: () => _showLanguagePicker(context, ref),
              ),
            ],
          ),

          // Support section
          _SheetSection(
            label: l10n.settingsSupport,
            children: [
              _SheetRow(
                icon: Icons.help_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsHelpCenter,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.info_outline_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsAbout,
                onTap: () => _comingSoon(context),
              ),
              _SheetRow(
                icon: Icons.gavel_rounded,
                iconBg: const Color(0xFFD0EBDA),
                iconColor: kForest,
                label: l10n.settingsTerms,
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
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                children: [
                  _SheetRow(
                    icon: Icons.logout_rounded,
                    iconBg: const Color(0xFFD0EBDA),
                    iconColor: kForest,
                    label: l10n.settingsLogout,
                    showChevron: false,
                    onTap: onLogout,
                  ),
                  Container(
                      height: 1,
                      margin: const EdgeInsets.only(left: 56),
                      color: kBorder),
                  _SheetRow(
                    icon: Icons.delete_outline_rounded,
                    iconBg: const Color(0xFFFFDAD6),
                    iconColor: const Color(0xFFBA1A1A),
                    label: l10n.settingsDeleteAccount,
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
      SnackBar(content: Text(AppLocalizations.of(context)!.comingSoon)),
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
              color: kText2,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
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
                      style: const TextStyle(fontSize: 13, color: kText2)),
                  const SizedBox(width: 4),
                ],
                if (showChevron)
                  const Icon(Icons.chevron_right, size: 20, color: kText3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 56),
              color: kBorder),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Travel identity edit widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Tappable row for single-value country fields (Lives in).
/// Shows icon box + uppercase label + current flag+name + chevron.
class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? countryCode;
  final VoidCallback onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.countryCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final country = countryCode != null ? countryByCode(countryCode!) : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
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
                      color: kText2,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    country != null
                        ? '${country.flag} ${country.name}'
                        : 'Select a country',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: country != null ? kBark : kText3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: kText3),
          ],
        ),
      ),
    );
  }
}

/// Chips row for multi-value fields (Passport countries, Languages).
/// Shows icon box + uppercase label + removable chips + dashed "Add" button.
class _CodeChipsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> codes;
  final String Function(String code) labelFor;
  final VoidCallback onAdd;
  final void Function(String code) onRemove;

  const _CodeChipsRow({
    required this.icon,
    required this.label,
    required this.codes,
    required this.labelFor,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                    color: kText2,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...codes.map((code) => _Chip(
                          label: labelFor(code),
                          onRemove: () => onRemove(code),
                        )),
                    _AddChip(onTap: onAdd),
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

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _Chip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD0EBDA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kForest,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 14, color: kForest),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kText3, style: BorderStyle.solid, width: 1.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: kText2),
            SizedBox(width: 3),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kText2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
