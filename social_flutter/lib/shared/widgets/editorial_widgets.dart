// shared/widgets/editorial_widgets.dart
//
// Reusable Editorial-style building blocks used across profile and search
// screens.  Extracted from follow_list_screen so multiple screens share one
// implementation.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

// ── AvatarInitials ────────────────────────────────────────────────────────────
// 44 px circle — shows the real avatar when available, otherwise the first
// letter(s) of `name` on a deterministic color-coded background.

class AvatarInitials extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  static const _size = 44.0;

  const AvatarInitials({super.key, required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return UserAvatar(avatarUrl: avatarUrl, radius: _size / 2);
    }
    final initials = _initials(name);
    final palette = _palette(nt, name);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(color: palette.$1, shape: BoxShape.circle),
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
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static (Color, Color) _palette(NtripiColors nt, String name) {
    final palettes = nt.avatarPairs;
    int h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return palettes[h % palettes.length];
  }
}

// ── OwnerAttributionRow ───────────────────────────────────────────────────────
// "Whose trip is this?" — avatar + display name over @handle, with an optional
// trailing action. Sits above an ItinerarySummaryCard on both the discovery
// feed and the Shared segment of the Itineraries tab.
//
// Takes plain strings rather than a model so shared/ never has to import a
// feature's domain layer.

class OwnerAttributionRow extends StatelessWidget {
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final Widget? trailing;

  const OwnerAttributionRow({
    super.key,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final hasDisplay = displayName != null && displayName!.isNotEmpty;
    final title =
        hasDisplay ? displayName! : (username != null ? '@$username' : '?');
    // Only show the @handle as a subtitle when we already used the display name
    // on the title line — otherwise it would duplicate.
    final subtitle = (hasDisplay && username != null) ? '@$username' : null;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2, top: 4, bottom: 8),
      child: Row(
        children: [
          AvatarInitials(name: title, avatarUrl: avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: nt.text2),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── EditorialTopBar ───────────────────────────────────────────────────────────
// Standard top bar for secondary screens: back arrow + title + optional actions.
// Replaces the Material AppBar throughout the app.

class EditorialTopBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  // Replaces the back arrow — a modal edit form cancels rather than navigates.
  final Widget? leading;
  // Only for a leading/trailing pair (Cancel … Save), where a left-aligned
  // title would sit off-centre between two controls of unequal width.
  final bool centerTitle;

  const EditorialTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          leading ??
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: nt.bark,
                // Material's own AppBar back button carries this; an icon with
                // no label is unreadable to a screen reader without it.
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
          Expanded(
            child: Text(
              title,
              textAlign: centerTitle ? TextAlign.center : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: nt.bark,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

// ── EditorialDivider ──────────────────────────────────────────────────────────
// The hairline under an EditorialTopBar, which doubles as the progress bar for
// a screen that reloads itself on open.
//
// That reload deliberately leaves the previous content on screen (see
// silentRefresh), so without this there is nothing at all to say a request is
// in flight — the list simply sits there until rows change under the user.
// A RefreshIndicator can't fill the gap: it only draws for a real drag.
//
// The 2 px box is fixed and the idle hairline is top-aligned inside it, so
// switching between the two never nudges the content below by a pixel.

class EditorialDivider extends StatelessWidget {
  final bool loading;

  const EditorialDivider({super.key, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return SizedBox(
      height: 2,
      child: loading
          ? LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: nt.border,
              color: nt.forest,
            )
          : Align(
              alignment: Alignment.topCenter,
              child: Container(height: 1, color: nt.border),
            ),
    );
  }
}

// ── SectionLabel ──────────────────────────────────────────────────────────────
// Uppercase label row with an optional small leading icon.  Used as a section
// header above a SectionCard.

class SectionLabel extends StatelessWidget {
  // Nullable: the form screens' headers carry no icon, and inventing one to
  // satisfy this widget would be a redesign rather than an alignment.
  final IconData? icon;
  final String label;
  // Nullable: theme lookups aren't const, so the default resolves in build.
  final Color? color;

  const SectionLabel({
    super.key,
    this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.nt.text2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
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

// ── SectionCard ───────────────────────────────────────────────────────────────
// White rounded-border card that groups a list of row widgets.

class SectionCard extends StatelessWidget {
  final List<Widget> children;
  // Both default to the behaviour every existing caller already gets, so the
  // form screens can adopt this widget without moving anyone else's pixels.
  //
  // Clipping is opt-in on purpose: the whole app draws with this card, and
  // notifications_screen deliberately clips its own swipe pane instead of
  // paying for a layer on every card in every list.
  final Clip clipBehavior;
  final CrossAxisAlignment crossAxisAlignment;

  const SectionCard({
    super.key,
    required this.children,
    this.clipBehavior = Clip.none,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: nt.border),
      ),
      clipBehavior: clipBehavior,
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ── FieldDivider ──────────────────────────────────────────────────────────────
// Hairline between two rows of a SectionCard, inset past the card's padding so
// it reads as a separator rather than a full-width rule.

class FieldDivider extends StatelessWidget {
  const FieldDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: context.nt.border,
      margin: const EdgeInsetsDirectional.only(start: 16),
    );
  }
}

// ── EditorialRow ──────────────────────────────────────────────────────────────
// Icon-badge + label row for a SectionCard.  Extracted from the profile
// settings sheet's private _SheetRow once Help Center and About needed the same
// row; the sheet and those screens must stay visually identical, and two copies
// would drift.

class EditorialRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String? detail;
  // Second line under the label. `detail` sits on the trailing edge instead,
  // which leaves no room once `trailing` is a control rather than a chevron.
  final String? subtitle;
  final bool showChevron;
  final bool isLast;
  final VoidCallback? onTap;
  // Replaces the chevron — for rows that toggle in place rather than navigate.
  final Widget? trailing;

  const EditorialRow({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.detail,
    this.subtitle,
    this.showChevron = true,
    this.isLast = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: nt.bark,
                        ),
                      ),
                      // Under the label, not beside it — a toggle row has no
                      // room left for an explanation on the trailing edge.
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: nt.text2,
                          ),
                        ),
                    ],
                  ),
                ),
                if (detail != null) ...[
                  Text(
                    detail!,
                    style: TextStyle(fontSize: 13, color: nt.text2),
                  ),
                  const SizedBox(width: 4),
                ],
                if (trailing != null)
                  trailing!
                else if (showChevron)
                  Icon(Icons.chevron_right, size: 20, color: nt.text3),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            margin: const EdgeInsetsDirectional.only(start: 56),
            color: nt.border,
          ),
      ],
    );
  }
}

// ── RefreshableCenter ─────────────────────────────────────────────────────────
// Pull-to-refresh over a state that has nothing to scroll.
//
// A RefreshIndicator is normally wrapped around the populated list, which puts
// it inside the `data` branch behind an isEmpty early return — so the two states
// where the user most wants to re-check, an empty list and a failed load, are
// the two with no way to ask again. AlwaysScrollableScrollPhysics is what lets a
// viewport shorter than its box still register the drag; the LayoutBuilder is
// what keeps the child vertically centred while remaining scrollable.

class RefreshableCenter extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const RefreshableCenter({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
