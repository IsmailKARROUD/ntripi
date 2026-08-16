// features/feed/presentation/widgets/feed_card.dart — a discovery-feed entry:
// an owner attribution row above the reused ItinerarySummaryCard.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';

class FeedCard extends ConsumerWidget {
  final FeedItem item;
  const FeedCard({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final owner = item.owner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerAttributionRow(
          displayName: owner.displayName,
          username: owner.username,
          avatarUrl: owner.avatarUrl,
          // Share the itinerary via the OS share sheet (reuses ShareService).
          trailing: IconButton(
            icon: Icon(Icons.share_rounded, size: 20, color: nt.text2),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.shareTooltip,
            onPressed: () => ref
                .read(shareServiceProvider)
                .shareItinerary(item.itinerary, l10n),
          ),
        ),
        // Reuse the shared card unchanged; feed cards don't offer delete.
        ItinerarySummaryCard(itinerary: item.itinerary),
      ],
    );
  }
}
