import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

/// Blurs [child] and swallows all pointer events while [saving] is true,
/// showing a centered [NTripiRingLoader]. Wrap the root widget of any screen
/// or sheet that fires a mutation request.
class SavingOverlay extends StatelessWidget {
  const SavingOverlay({
    super.key,
    required this.saving,
    required this.child,
    this.tint = kSand,
    this.loaderSize = 56,
    this.borderRadius,
  });

  final bool saving;
  final Widget child;

  /// Scrim color over the blur — pass [kSurface] on white-background screens.
  final Color tint;

  /// 56 for full screens, 40 for bottom sheets.
  final double loaderSize;

  /// Match the sheet's rounded corners when content starts at its very top.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Built conditionally (not faded) — a mounted BackdropFilter forces a
        // saveLayer every frame even at sigma 0.
        if (saving)
          Positioned.fill(
            child: AbsorbPointer(
              // Always clip — BackdropFilter otherwise blurs past the overlay
              // rect inside unclipped bottom sheets.
              child: ClipRRect(
                borderRadius: borderRadius ?? BorderRadius.zero,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    color: tint.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: NTripiRingLoader(size: loaderSize),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
