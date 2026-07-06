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
    final l10n = AppLocalizations.of(context)!;
    final owner = item.owner;
    final hasDisplay =
        owner.displayName != null && owner.displayName!.isNotEmpty;
    final title = hasDisplay
        ? owner.displayName!
        : (owner.username != null ? '@${owner.username}' : '?');
    // Only show the @handle as a subtitle when we already used the display name
    // on the title line — otherwise it would duplicate.
    final subtitle =
        (hasDisplay && owner.username != null) ? '@${owner.username}' : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 4, bottom: 8),
          child: Row(
            children: [
              AvatarInitials(name: title, avatarUrl: owner.avatarUrl),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kBark,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: kText2),
                      ),
                  ],
                ),
              ),
              // Share the itinerary via the OS share sheet (reuses ShareService).
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 20, color: kText2),
                visualDensity: VisualDensity.compact,
                tooltip: l10n.shareTooltip,
                onPressed: () => ref
                    .read(shareServiceProvider)
                    .shareItinerary(item.itinerary, l10n),
              ),
            ],
          ),
        ),
        // Reuse the shared card unchanged; feed cards don't offer delete.
        ItinerarySummaryCard(itinerary: item.itinerary),
      ],
    );
  }
}
