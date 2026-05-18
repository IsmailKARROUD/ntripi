import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Pill badge showing itinerary visibility.
///
/// [onDark] — true when rendered over a dark/image background (itinerary
/// detail hero): renders white text/icon on a frosted white overlay.
/// Default (false) renders brand-colored text/icon on a tinted background
/// (summary card).
class VisibilityBadge extends StatelessWidget {
  final ItineraryVisibility visibility;
  final bool onDark;

  const VisibilityBadge({
    super.key,
    required this.visibility,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final icon = switch (visibility) {
      ItineraryVisibility.public => Icons.public_rounded,
      ItineraryVisibility.followers => Icons.group_rounded,
      ItineraryVisibility.restricted => Icons.key_rounded,
      ItineraryVisibility.onlyMe => Icons.lock_rounded,
    };
    final label = switch (visibility) {
      ItineraryVisibility.public => l10n.visibilityPublic,
      ItineraryVisibility.followers => l10n.visibilityFollowers,
      ItineraryVisibility.restricted => l10n.visibilityRestricted,
      ItineraryVisibility.onlyMe => l10n.visibilityOnlyMe,
    };

    final Color foreground;
    final Color background;

    if (onDark) {
      foreground = Colors.white;
      background = const Color(0x88000000); // frosted black overlay
    } else {
      foreground = switch (visibility) {
        ItineraryVisibility.public => kCanopy,
        ItineraryVisibility.followers => kText2,
        ItineraryVisibility.restricted => kRatingOrange,
        ItineraryVisibility.onlyMe => kText3,
      };
      background = foreground.withValues(alpha: 0.12);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
