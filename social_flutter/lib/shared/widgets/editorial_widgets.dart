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
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return UserAvatar(avatarUrl: avatarUrl, radius: _size / 2);
    }
    final initials = _initials(name);
    final palette = _palette(name);
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

// ── EditorialTopBar ───────────────────────────────────────────────────────────
// Standard top bar for secondary screens: back arrow + title + optional actions.
// Replaces the Material AppBar throughout the app.

class EditorialTopBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  const EditorialTopBar({
    super.key,
    required this.title,
    this.actions = const [],
  });

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
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kBark,
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

// ── SectionLabel ──────────────────────────────────────────────────────────────
// Uppercase label row with a small leading icon.  Used as a section header
// above a SectionCard.

class SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const SectionLabel({
    super.key,
    required this.icon,
    required this.label,
    this.color = kText2,
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

// ── SectionCard ───────────────────────────────────────────────────────────────
// White rounded-border card that groups a list of row widgets.

class SectionCard extends StatelessWidget {
  final List<Widget> children;
  const SectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
