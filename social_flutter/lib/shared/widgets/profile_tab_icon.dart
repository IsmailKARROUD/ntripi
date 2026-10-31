// shared/widgets/profile_tab_icon.dart — the Profile tab's icon in the bottom bar.
//
// The signed-in user's photo in a circle, or the person icon the tab always
// had: when there is no photo, while it loads, and when it fails to load.

import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';

class ProfileTabIcon extends StatelessWidget {
  /// The user's photo; null draws the person icon.
  final ImageProvider? photo;

  /// The Profile tab is the open one.
  final bool selected;

  const ProfileTabIcon({super.key, this.photo, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final fallback = Icon(
      selected ? Icons.person_rounded : Icons.person_outline_rounded,
    );
    final photo = this.photo;
    if (photo == null) return fallback;
    // The bar sizes a tab by its icon: a bigger box would put the Profile
    // label lower than the others.
    return SizedBox.square(
      dimension: iconTheme.size ?? 24,
      child: Image(
        image: photo,
        fit: BoxFit.cover,
        // The tab's label already names it.
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame == null && !wasSynchronouslyLoaded) return fallback;
          return DecoratedBox(
            // A photo cannot turn green like the other tabs' icons, so the
            // open tab rings it in the bar's selected color.
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(
                      color: iconTheme.color ?? context.nt.forest,
                      width: 2,
                    )
                  : null,
            ),
            // The ring's width, kept in both states so the photo never moves.
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipOval(child: child),
            ),
          );
        },
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
