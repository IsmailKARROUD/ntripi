// features/feed/presentation/widgets/feed_card.dart — a discovery-feed entry:
// an owner attribution row above the reused ItinerarySummaryCard.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
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
    final translation = item.titleTranslation;
    final lang =
        ref.watch(localeProvider.select((locale) => locale.languageCode));

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
        ItinerarySummaryCard(
          itinerary: item.itinerary,
          // A page fetched before a language switch carries the old language's
          // titles until the refetch lands; those are not the reader's.
          title: translation != null && translation.lang == lang
              ? FeedTitle(
                  original: item.itinerary.title,
                  sourceLang: item.itinerary.sourceLang,
                  translation: translation,
                )
              : null,
        ),
      ],
    );
  }
}

/// A feed title that has a translation.
///
/// Written in a language the reader lists as spoken on their profile, it shows
/// as written, one tap from the translation. Otherwise it shows translated and
/// marked, one tap from the original. Neither tap is a request: the
/// translation came with the page.
class FeedTitle extends ConsumerStatefulWidget {
  const FeedTitle({
    super.key,
    required this.original,
    required this.sourceLang,
    required this.translation,
  });

  final String original;
  final String? sourceLang;
  final TitleTranslation translation;

  @override
  ConsumerState<FeedTitle> createState() => _FeedTitleState();
}

class _FeedTitleState extends ConsumerState<FeedTitle> {
  /// The reader's own choice for this card; once they tap, it outranks the
  /// spoken-languages rule.
  bool? _showTranslation;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    // Profile codes are upper case ("FR"); detected languages are lower case.
    final spoken = ref.watch(
            myProfileProvider.select((profile) => profile.value?.languages)) ??
        const <String>[];
    final source = widget.sourceLang;
    final speaks =
        source != null && spoken.any((code) => code.toLowerCase() == source);
    final translated = _showTranslation ?? !speaks;
    final style = ItinerarySummaryCard.titleStyle(nt);

    final Widget text = translated
        ? Directionality(
            textDirection: isRtlLanguage(widget.translation.lang)
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Text(
              widget.translation.text,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : Text(widget.original, style: style, overflow: TextOverflow.ellipsis);

    final action =
        translated ? l10n.translationSeeOriginal : l10n.translationSeeTranslation;
    void flip() => setState(() => _showTranslation = !translated);
    return Row(
      children: [
        Flexible(child: text),
        // Its own node: inside the card's it would merge into the card's label
        // and lose the action that flips it.
        Semantics(
          container: true,
          button: true,
          label: translated
              ? '${l10n.translationTranslatedMarker}. $action'
              : action,
          onTap: flip,
          excludeSemantics: true,
          child: Tooltip(
            message: action,
            excludeFromSemantics: true,
            child: GestureDetector(
              // Claims the tap, so flipping the title never opens the trip.
              behavior: HitTestBehavior.opaque,
              onTap: flip,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Icon(
                  Icons.translate_rounded,
                  size: 15,
                  // Lit while it marks a translation; quiet while it offers one.
                  color: translated ? nt.forest : nt.text3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
