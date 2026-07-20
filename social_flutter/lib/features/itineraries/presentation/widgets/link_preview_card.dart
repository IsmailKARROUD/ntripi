// presentation/widgets/link_preview_card.dart — WhatsApp/Telegram-style Open
// Graph card for a stop's saved Google Maps link.
//
// It watches [linkPreviewProvider] (a client-side, mobile-only unfurl) and:
//   * loading  → a compact skeleton row.
//   * data     → image (hotlinked, short-TTL cached) + title + description.
//   * null/web → a plain "Opens in Google Maps" fallback row (web can't fetch
//                cross-origin, and any fetch failure resolves to null too).
// Tapping anywhere opens the link in Google Maps.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/data/link_preview_service.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class LinkPreviewCard extends ConsumerWidget {
  final String url;

  const LinkPreviewCard({super.key, required this.url});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(linkPreviewProvider(url));

    void open() => ref.read(mapsLauncherServiceProvider).openUrl(url);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: nt.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: async.when(
            loading: () => _fallbackRow(nt, l10n, loading: true),
            error: (_, _) => _fallbackRow(nt, l10n),
            data:
                (preview) =>
                    preview == null || !preview.hasContent
                        ? _fallbackRow(nt, l10n)
                        : _card(context, nt, l10n, preview),
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    NtripiColors nt,
    AppLocalizations l10n,
    LinkPreview preview,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview.imageUrl != null)
          SizedBox(
            height: 150,
            child: CachedNetworkImage(
              imageUrl: preview.imageUrl!,
              // Short-TTL, separate namespace — a transient copy of a hotlinked
              // third-party image, never a durable re-host.
              cacheManager: NtripiLinkPreviewCacheManager(),
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: nt.mist),
              // A dead og:image URL must not blank the whole card — hide it and
              // keep the title/description below.
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.title != null)
                Text(
                  preview.title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
              if (preview.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  preview.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: nt.text2),
                ),
              ],
              const SizedBox(height: 8),
              _sourceRow(nt, l10n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceRow(NtripiColors nt, AppLocalizations l10n) {
    return Row(
      children: [
        Icon(Icons.map_rounded, size: 14, color: nt.forest),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.linkPreviewOpensInMaps,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: nt.forest,
            ),
          ),
        ),
        Icon(Icons.open_in_new_rounded, size: 14, color: nt.forest),
      ],
    );
  }

  // Used while loading and whenever there's no usable preview (web, errors,
  // tag-less pages). Still fully tappable via the enclosing InkWell.
  Widget _fallbackRow(
    NtripiColors nt,
    AppLocalizations l10n, {
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.map_rounded, size: 16, color: nt.forest),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loading ? l10n.linkPreviewLoading : l10n.linkPreviewOpensInMaps,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: nt.forest,
              ),
            ),
          ),
          if (loading)
            const NTripiRingLoader(size: 16)
          else
            Icon(Icons.open_in_new_rounded, size: 14, color: nt.forest),
        ],
      ),
    );
  }
}
