// presentation/widgets/link_preview_card.dart — the stop page's map card.
//
// Three modes:
//   * default ctor — a stop's saved Google Maps URL, unfurled client-side (the
//     stop page keeps this preview by the user's choice; the add/edit form
//     never fetches a link — see stop_form_screen.dart).
//   * .coordinates — a coordinate stop: a pin at its exact lat/lng; tapping
//     opens the map-provider picker sheet.
//   * .googlePlace — a Google place: the map by its place ID; tapping opens it
//     in Google Maps by the same ID.
//
// Every map is a GoogleMapEmbed of a page on our own server (GoogleEmbed),
// shown only while the server has its embed key (placesConfigProvider). The
// unfurl (mobile only — web can't read Google cross-origin) supplies, for a
// link, the name and coordinates the map is drawn from when the link's own
// text carries no place ID; nothing it reads is ever stored.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/google_embed_urls.dart';
import 'package:ntripi/features/itineraries/data/link_preview_service.dart';
import 'package:ntripi/features/itineraries/domain/map_point.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/google_map_embed.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/open_in_maps_sheet.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

enum _CardMode { link, coordinates, googlePlace }

class LinkPreviewCard extends ConsumerWidget {
  final _CardMode _mode;
  // Link mode: the saved Google Maps URL.
  final String? url;
  // Coordinate mode: exact stop coords → deterministic map, no unfurl.
  final double? lat;
  final double? lng;
  // Coordinate mode only: names the dropped pin in the provider picker sheet.
  final String? label;
  // Google place mode, and link mode when the server read an ID from the link.
  final String? placeId;
  // Google place mode: the text Open in Google Maps falls back to.
  final String? query;

  // Link mode. [placeId] is the one the server read out of the link's text,
  // when it had one: the most precise map, needing no unfurl.
  const LinkPreviewCard({super.key, required String this.url, this.placeId})
      : _mode = _CardMode.link,
        lat = null,
        lng = null,
        label = null,
        query = null;

  // Coordinate-only stop: the map straight from lat/lng and, on tap, a choice
  // of map apps — no unfurl, no title/description.
  const LinkPreviewCard.coordinates({
    super.key,
    required double this.lat,
    required double this.lng,
    this.label,
  })  : _mode = _CardMode.coordinates,
        url = null,
        placeId = null,
        query = null;

  // A Google place: only Google knows where it is, so it opens in Google Maps.
  const LinkPreviewCard.googlePlace({
    super.key,
    required String this.placeId,
    required String this.query,
  })  : _mode = _CardMode.googlePlace,
        url = null,
        lat = null,
        lng = null,
        label = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final mapsOn = ref.watch(placesConfigProvider).value?.googleMaps ?? false;
    final language = GoogleEmbed.languageOf(context);
    final maps = ref.read(mapsLauncherServiceProvider);

    Uri? mapOf(MapPoint? point) =>
        mapsOn && point != null ? GoogleEmbed.point(point, language) : null;

    switch (_mode) {
      case _CardMode.coordinates:
        final embedUrl = mapOf(CoordPoint(lat!, lng!));
        return _shell(
          nt,
          onTap: () => showOpenInMapsSheet(
              context: context, lat: lat!, lng: lng!, label: label),
          child: embedUrl == null
              ? _fallbackRow(nt, l10n)
              : _card(context, nt, l10n, null, embedUrl),
        );
      case _CardMode.googlePlace:
        final embedUrl = mapOf(PlacePoint(placeId!, query!));
        return _shell(
          nt,
          onTap: () => maps.openGooglePlace(placeId!, query!),
          child: embedUrl == null
              ? _fallbackRow(nt, l10n)
              : _card(context, nt, l10n, null, embedUrl),
        );
      case _CardMode.link:
        break;
    }

    // Link mode: unfurl the saved URL client-side (mobile only) and render.
    final async = ref.watch(linkPreviewProvider(url!));

    // Copy the unfurled place title; no-op when there's no title yet (loading,
    // errors, or web where the cross-origin unfurl is blocked and title is null).
    void copy() {
      final title = async.value?.title?.trim();
      if (title == null || title.isEmpty) return;
      Clipboard.setData(ClipboardData(text: title));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkPreviewTitleCopied)),
      );
    }

    return _shell(
      nt,
      onTap: () => maps.openUrl(url!),
      onLongPress: copy,
      child: async.when(
        loading: () => _fallbackRow(nt, l10n, loading: true),
        error: (_, _) => _fallbackRow(nt, l10n),
        data: (preview) {
          // The map even when the unfurl gave nothing (web): a place ID or a
          // full link's coordinates are in its own text.
          final embedUrl = mapsOn ? _linkMap(preview, language) : null;
          final hasContent = preview != null && preview.hasContent;
          if (embedUrl != null || hasContent) {
            return _card(context, nt, l10n, preview, embedUrl);
          }
          // Nothing to map. On web that means an unresolvable short link (the
          // unfurl can't run cross-origin) — tell the viewer the map preview
          // lives in the app, but keep the tappable "Opens in Google Maps" row.
          return kIsWeb && mapsOn
              ? _webNoEmbed(nt, l10n)
              : _fallbackRow(nt, l10n);
        },
      ),
    );
  }

  // Link-mode map, most precise first: a place ID (the server's, or one in the
  // link's text) → the unfurl's coordinates → the unfurl's place name → the
  // coordinates in the link's text. Only the first and last need no unfurl.
  Uri? _linkMap(LinkPreview? preview, String language) {
    final id = placeId ?? extractPlaceId(url!);
    if (id != null) return GoogleEmbed.point(PlacePoint(id, ''), language);
    final pLat = preview?.lat;
    final pLng = preview?.lng;
    if (pLat != null && pLng != null) {
      return GoogleEmbed.point(CoordPoint(pLat, pLng), language);
    }
    final title = preview?.title?.trim();
    if (title != null && title.isNotEmpty) {
      return GoogleEmbed.search(title, language);
    }
    final coords = extractMapCoords(url!);
    return coords == null
        ? null
        : GoogleEmbed.point(CoordPoint(coords.$1, coords.$2), language);
  }

  // Shared card chrome: the tappable, bordered, clipped container. onLongPress
  // doubles as onDoubleTap (copy-title in link mode; unused otherwise).
  Widget _shell(
    NtripiColors nt, {
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onLongPress,
        borderRadius: BorderRadius.circular(NtripiRadius.tile),
        child: Container(
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(NtripiRadius.tile),
            border: Border.all(color: nt.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  // Coordinate-mode taps open the provider picker; the others open Google
  // Maps directly — so the row's action label differs.
  String _openLabel(AppLocalizations l10n) => _mode == _CardMode.coordinates
      ? l10n.openInMaps
      : l10n.linkPreviewOpensInMaps;

  Widget _card(
    BuildContext context,
    NtripiColors nt,
    AppLocalizations l10n,
    LinkPreview? preview,
    Uri? embedUrl,
  ) {
    final title = preview?.title;
    final description = preview?.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embedUrl != null) GoogleMapEmbed(url: embedUrl),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description,
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
            _openLabel(l10n),
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

  // Used while loading and whenever there's no map (no embed key on the
  // server, web, errors, tag-less pages). Still tappable via the InkWell.
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
              loading ? l10n.linkPreviewLoading : _openLabel(l10n),
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

  // Web link mode with nothing to map (a short link the browser can't resolve
  // cross-origin): the notice sits above the still-tappable open-in-maps row.
  Widget _webNoEmbed(NtripiColors nt, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mobileNoticeRow(nt, l10n),
        _fallbackRow(nt, l10n),
      ],
    );
  }

  // Muted line telling the viewer the map preview is only in the app.
  Widget _mobileNoticeRow(NtripiColors nt, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Icon(Icons.smartphone_rounded, size: 16, color: nt.text2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.linkPreviewMapMobileOnly,
              style: TextStyle(fontSize: 12, color: nt.text2),
            ),
          ),
        ],
      ),
    );
  }
}
