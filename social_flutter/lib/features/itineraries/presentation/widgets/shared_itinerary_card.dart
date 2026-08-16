// features/itineraries/presentation/widgets/shared_itinerary_card.dart — a trip
// somebody else owns and granted the viewer edit rights on: owner attribution
// plus an "Editor" badge above the reused ItinerarySummaryCard.
//
// Same composition as FeedCard, with two deliberate differences: no share
// action (a restricted trip is not the editor's to circulate) and no
// onLongPress, because deleting an itinerary is owner-only.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

class SharedItineraryCard extends StatelessWidget {
  final FeedItem item;

  const SharedItineraryCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final owner = item.owner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerAttributionRow(
          displayName: owner.displayName,
          username: owner.username,
          avatarUrl: owner.avatarUrl,
          trailing: const _EditorBadge(),
        ),
        ItinerarySummaryCard(itinerary: item.itinerary),
      ],
    );
  }
}

// Says why a trip the viewer does not own is in their list at all.
class _EditorBadge extends StatelessWidget {
  const _EditorBadge();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // forest tint, not a flat fill — has to stay legible on both themes.
        color: nt.forest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, size: 13, color: nt.forest),
          const SizedBox(width: 5),
          Text(
            l10n.editorBadgeLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: nt.forest,
            ),
          ),
        ],
      ),
    );
  }
}
