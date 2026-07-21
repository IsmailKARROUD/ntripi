// presentation/widgets/link_preview_card.dart — WhatsApp/Telegram-style card for
// a stop's saved Google Maps link.
//
// Watches [linkPreviewProvider] (a client-side unfurl; mobile only — web can't
// read Google cross-origin, so on web the preview resolves to null) and renders:
//   * a Google Maps Embed map when a key + a query exist. The query comes from
//     the unfurl (place name / coords) or, when there's no unfurl (web), from
//     coords embedded in the pasted URL. Mobile embeds via webview_flutter; web
//     via a browser <iframe> (MapEmbedWebView).
//   * title + description when the unfurl provided them.
//   * otherwise a plain "Opens in Google Maps" fallback row.
// Tapping the card (outside the interactive map) opens the link in Google Maps.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/data/link_preview_service.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/map_embed_web_view.dart';
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        onTap: open,
        onLongPress: copy,
        onDoubleTap: copy,
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
            data: (preview) {
              // Build the map even when the unfurl gave nothing (web): a full
              // pasted URL still yields coords. Show the card if there's a map
              // OR unfurled text; otherwise the plain fallback row.
              final embedUrl = _embedUrl(preview);
              final hasContent = preview != null && preview.hasContent;
              return embedUrl == null && !hasContent
                  ? _fallbackRow(nt, l10n)
                  : _card(context, nt, l10n, preview, embedUrl);
            },
          ),
        ),
      ),
    );
  }

  // Builds the Maps Embed API URL, or null when there's no key or no usable
  // query. `place` mode drops a marker for both a "lat,lng" and a free-text
  // place-name query. Query priority: unfurl coords → unfurl place name → coords
  // embedded in the pasted link (the only source on web, where the cross-origin
  // unfurl is blocked). No kIsWeb gate — web renders the same URL in an <iframe>.
  String? _embedUrl(LinkPreview? preview) {
    if (kGoogleMapsEmbedApiKey.isEmpty) return null;
    final lat = preview?.lat;
    final lng = preview?.lng;
    final title = preview?.title?.trim();
    String? q;
    if (lat != null && lng != null) {
      q = '$lat,$lng';
    } else if (title != null && title.isNotEmpty) {
      q = title;
    } else {
      final c = extractMapCoords(url); // pasted full URL may carry @lat,lng
      if (c != null) q = '${c.$1},${c.$2}';
    }
    if (q == null) return null;
    return 'https://www.google.com/maps/embed/v1/place'
        '?key=$kGoogleMapsEmbedApiKey'
        '&q=${Uri.encodeComponent(q)}'
        '&zoom=12';
  }

  Widget _card(
    BuildContext context,
    NtripiColors nt,
    AppLocalizations l10n,
    LinkPreview? preview,
    String? embedUrl,
  ) {
    final title = preview?.title;
    final description = preview?.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embedUrl != null)
          SizedBox(
            height: 180,
            // Mobile embeds the iframe inside a webview; web renders a real
            // <iframe> (webview_flutter has no web backend wired up here).
            child: kIsWeb
                ? MapEmbedWebView(embedUrl: embedUrl)
                : IgnorePointer(
                    ignoring: true,
                    child: _MapEmbedView(embedUrl: embedUrl),
                  ),
          ),
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

/// Renders the Google Maps Embed iframe. Stateful so it owns the controller
/// across rebuilds. Navigation is locked to Google's own hosts — the embed's
/// "View larger map" links must not hijack the webview; the card's outer InkWell
/// opens the real Google Maps app instead. Eager gestures let the map pan/zoom
/// even though it sits inside the tappable card and the scrollable form.
class _MapEmbedView extends StatefulWidget {
  final String embedUrl;

  const _MapEmbedView({required this.embedUrl});

  @override
  State<_MapEmbedView> createState() => _MapEmbedViewState();
}

class _MapEmbedViewState extends State<_MapEmbedView> {
  late final WebViewController _controller;

  // Wraps the Google Embed URL inside an HTML string with a full-size <iframe>
  String _buildIframeHtml(String url) {
    return '''
      <!DOCTYPE html>
      <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: transparent; }
            iframe { width: 100%; height: 100%; border: 0; }
          </style>
        </head>
        <body>
          <iframe 
            src="$url" 
            allowfullscreen 
            loading="lazy" 
            referrerpolicy="no-referrer-when-downgrade">
          </iframe>
        </body>
      </html>
    ''';
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final host = Uri.tryParse(req.url)?.host ?? '';
            // NOTE: `host.isEmpty` MUST be allowed so loadHtmlString's initial page isn't blocked!
            final ok = host.isEmpty ||
                host == 'google.com' ||
                host.endsWith('.google.com') ||
                host.endsWith('.gstatic.com');
            return ok
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_buildIframeHtml(widget.embedUrl));
  }

  @override
  void didUpdateWidget(covariant _MapEmbedView old) {
    super.didUpdateWidget(old);
    if (old.embedUrl != widget.embedUrl) {
      _controller.loadHtmlString(_buildIframeHtml(widget.embedUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: _controller,
    );
  }
}
