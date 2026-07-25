// features/profile/presentation/widgets/profile_chrome.dart
//
// Shared editorial chrome for the profile screens (my_profile_screen and
// user_profile_screen). Centralizes the OSM hero, overlapping avatar,
// tally tiles and glass-blur top buttons so both screens stay in sync.

import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/fullscreen_image_viewer.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

/// Renders the OSM map hero (260 px) with the avatar + name/handle
/// row overlapping it by 36 px at the bottom. Used for both self
/// and other-user profiles via [isSelf].
class ProfileHeroAndIdentity extends StatelessWidget {
  final User user;
  final int totalStops;
  final bool isSelf;
  final bool isContentHidden;
  final String? headerLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onSettings;
  final String? coverImageUrl;
  final List<VisitedLocation> locations;
  final VoidCallback? onHeroTap;
  // Receives the global tap point so the viewer can grow out of it.
  final void Function(Offset globalPosition)? onAvatarTap;
  // Anchors the "add a profile photo" hint beak at the Edit pencil button.
  final GlobalKey? editButtonKey;

  const ProfileHeroAndIdentity({
    super.key,
    required this.user,
    required this.totalStops,
    this.isSelf = true,
    this.isContentHidden = false,
    this.headerLabel,
    this.onEdit,
    this.onSettings,
    this.coverImageUrl,
    this.locations = const [],
    this.onHeroTap,
    this.onAvatarTap,
    this.editButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH,
            child: ProfileMapHero(
              isSelf: isSelf,
              totalStops: totalStops,
              isPrivate: user.isPrivate,
              isContentHidden: isContentHidden,
              headerLabel: headerLabel,
              onEdit: onEdit,
              onSettings: onSettings,
              coverImageUrl: coverImageUrl,
              locations: locations,
              onHeroTap: onHeroTap,
              editButtonKey: editButtonKey,
            ),
          ),
          Positioned(
            top: heroH - overlap,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onAvatarTap == null
                      ? null
                      : (details) => onAvatarTap!(details.globalPosition),
                  child: AvatarWithBadge(
                    avatarUrl: user.avatarUrl,
                    isPrivate: user.isPrivate,
                  ),
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
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: nt.bark,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        user.handle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: nt.text2,
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

/// The 260 px map block at the top of the hero. Decorative non-interactive
/// OSM tiles + sand tint + gradient + chrome buttons + bottom label.
/// When [isContentHidden] is true, a blurred lock veil hides the map and the
/// bottom label is suppressed.
class ProfileMapHero extends StatelessWidget {
  final bool isSelf;
  final int totalStops;
  final bool isPrivate;
  final bool isContentHidden;
  final String? headerLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onSettings;
  final String? coverImageUrl;
  final List<VisitedLocation> locations;
  final VoidCallback? onHeroTap;
  final GlobalKey? editButtonKey;

  const ProfileMapHero({
    super.key,
    required this.isSelf,
    required this.totalStops,
    required this.isPrivate,
    this.isContentHidden = false,
    this.headerLabel,
    this.onEdit,
    this.onSettings,
    this.coverImageUrl,
    this.locations = const [],
    this.onHeroTap,
    this.editButtonKey,
  });

  String? _resolveCoverUrl() {
    final raw = coverImageUrl;
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('/') ? '$kApiBaseUrl$raw' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final label = headerLabel ?? l10n.whereIveBeen;
    final resolvedCover = _resolveCoverUrl();
    final hasCover = resolvedCover != null;
    // Blurred-map fallback shows over the OSM hero; hidden for the cover image
    // (cover should be clear) and hidden when isContentHidden (the lock veil
    // is the stronger signal).
    final showMapBlurAndCta = !hasCover && !isContentHidden;
    // A real cover opens full-screen on tap; the map fallback keeps its
    // existing "tap to see stops" behavior.
    final coverTappable = hasCover && !isContentHidden;
    final showHeroTapLayer = coverTappable || onHeroTap != null;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCover)
            CachedNetworkImage(
              imageUrl: resolvedCover,
              cacheManager: NtripiImageCacheManager(),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: nt.sand),
            )
          else
            IgnorePointer(
              child: FlutterMap(
                options: locations.isNotEmpty
                    ? MapOptions(
                        initialCameraFit: CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(
                            locations
                                .map((l) => LatLng(l.lat, l.lng))
                                .toList(),
                          ),
                          padding: const EdgeInsets.all(40),
                          // A single location (or all-identical points) yields
                          // zero-size bounds; without a finite cap flutter_map's
                          // fit computes zoom=Infinity -> NaN camera -> infinite
                          // tile grid -> main-thread ANR. Cap it.
                          maxZoom: 16,
                        ),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      )
                    : const MapOptions(
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
                    // Silently discard tile errors (offline / test mode).
                    errorTileCallback: (_, __, ___) {},
                  ),
                  if (locations.isNotEmpty)
                    MarkerLayer(
                      markers: locations
                          .map((loc) => Marker(
                                point: LatLng(loc.lat, loc.lng),
                                width: 14,
                                height: 14,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: nt.forest,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      // over OSM tiles — always light
                                      color: NtripiBrand.chrome,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),

          if (!hasCover) Container(color: NtripiColors.light.sand.withValues(alpha: 0.19)),

          // Privacy/aesthetic blur veil over the map fallback only.
          // Cover image stays clear; isContentHidden has its own stronger veil.
          if (showMapBlurAndCta)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: NtripiBrand.backdrop.withValues(alpha: 0.08),
                ),
              ),
            ),

          if (isContentHidden)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: NtripiColors.light.sand.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: NtripiBrand.scrimInk.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: NtripiBrand.backdrop.withValues(alpha: 0.2),
                        blurRadius: 20,
                      )
                    ],
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: NtripiBrand.chrome, size: 28),
                ),
              ),
            ),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.35, 0.55, 1.0],
                colors: [
                  // constant ink scrim — always sits over the hero imagery
                  NtripiBrand.scrimInk.withValues(alpha: 0.5),
                  NtripiBrand.scrimInk.withValues(alpha: 0),
                  NtripiBrand.scrimInk.withValues(alpha: 0),
                  NtripiBrand.scrimInk.withValues(alpha: 0.78),
                ],
              ),
            ),
          ),

          // Whole-hero tap target. Placed BEFORE the chrome buttons so the
          // buttons (drawn after) intercept their own taps first; this layer
          // catches everything else.
          if (showHeroTapLayer)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Capture the tap point so the cover grows out of it.
                onTapUp: (details) {
                  if (coverTappable) {
                    showFullscreenImage(context,
                        imageUrl: coverImageUrl!,
                        sourcePosition: details.globalPosition);
                  } else {
                    onHeroTap?.call();
                  }
                },
              ),
            ),

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
                          GlassIconButton(
                            key: editButtonKey,
                            icon: Icons.edit_outlined,
                            tooltip: l10n.editProfileTooltip,
                            onTap: onEdit,
                          ),
                          GlassIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: l10n.settingsTooltip,
                            onTap: onSettings,
                          ),
                        ]
                      : [
                          GlassIconButton(
                            icon: Icons.arrow_back,
                            tooltip: l10n.back,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          GlassIconButton(
                            icon: Icons.share_outlined,
                            tooltip: l10n.shareProfileTooltip,
                          ),
                        ],
                ),
              ),
            ),
          ),

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
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: NtripiBrand.chrome,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalStops > 0
                            ? l10n.stopCount(totalStops)
                            : l10n.noStopsYet,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: NtripiBrand.chrome,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // "Tap to see stops" CTA pill — centered on the map fallback.
          // Hidden when a cover image is shown or when content is locked.
          // IgnorePointer so taps fall through to the hero GestureDetector.
          if (showMapBlurAndCta)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: nt.buttonTransparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: NtripiBrand.chrome.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined,
                          size: 14, color: NtripiBrand.chrome),
                      const SizedBox(width: 6),
                      Text(
                        l10n.tapToSeeStops,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: NtripiBrand.chrome,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AvatarWithBadge extends StatelessWidget {
  final String? avatarUrl;
  final bool isPrivate;

  const AvatarWithBadge({
    super.key,
    required this.avatarUrl,
    required this.isPrivate,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            // constant white ring — always sits over the hero imagery
            color: NtripiBrand.chrome,
          ),
          child: ClipOval(
            child: UserAvatar(avatarUrl: avatarUrl, radius: 44),
          ),
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: NtripiBrand.chrome,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: NtripiBrand.chrome.withValues(alpha: 0.9),
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(
              isPrivate ? Icons.lock_rounded : Icons.public_rounded,
              size: 14,
              color: nt.forest,
            ),
          ),
        ),
      ],
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
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
                color: nt.buttonTransparent,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: NtripiBrand.chrome.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, color: NtripiBrand.chrome, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class Tally extends StatelessWidget {
  final int n;
  final String label;
  final VoidCallback? onTap;

  const Tally({super.key, required this.n, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: nt.bark,
                letterSpacing: -0.3,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: nt.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
