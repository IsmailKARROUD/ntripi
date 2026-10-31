// presentation/widgets/google_map_embed.dart — one Google map, display-only.
//
// Loads a page on our own server (GoogleEmbed) that frames Google's Maps Embed
// API. Phones load it in a WebView with a real https origin — so Google sees
// this site as the referrer, which the referrer-restricted key requires, where
// the old WebView built from an HTML string sent none. The web app frames the
// same page (MapEmbedWebView). The map takes no gestures on either platform:
// it sits in scrolling screens, and the caller's tap opens Google Maps or the
// route sheet instead.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/map_embed_web_view.dart';
import 'package:ntripi/shared/widgets/loaders.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The map WebView's navigation lock. The page itself may only be one of our
/// /embed pages; inside it, only Google's map frame and its assets. "View
/// larger map" and the like must not turn the box into a browser.
@visibleForTesting
bool embedNavigationAllowed(
  String url, {
  required bool isMainFrame,
  required String apiHost,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (isMainFrame) return uri.host == apiHost && uri.path.startsWith('/embed/');
  final host = uri.host;
  return host.isEmpty || // about:blank, Google's own placeholder frames
      host == 'google.com' ||
      host.endsWith('.google.com') ||
      host.endsWith('.gstatic.com');
}

class GoogleMapEmbed extends StatelessWidget {
  final Uri url;
  final double height;

  const GoogleMapEmbed({super.key, required this.url, this.height = 180});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: IgnorePointer(
        child: kIsWeb
            ? MapEmbedWebView(embedUrl: url.toString())
            : _MapEmbedView(url: url),
      ),
    );
  }
}

/// The WebView: stateful so it keeps its controller across rebuilds.
class _MapEmbedView extends StatefulWidget {
  final Uri url;

  const _MapEmbedView({required this.url});

  @override
  State<_MapEmbedView> createState() => _MapEmbedViewState();
}

class _MapEmbedViewState extends State<_MapEmbedView> {
  late final WebViewController _controller;
  // Covers the WebView's blank frame with a Ntripi loader until the map loads.
  bool _loading = true;

  static final String _apiHost = Uri.parse(kApiBaseUrl).host;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) => _allowed(request)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadRequest(widget.url);
  }

  bool _allowed(NavigationRequest request) => embedNavigationAllowed(
      request.url,
      isMainFrame: request.isMainFrame,
      apiHost: _apiHost);

  @override
  void didUpdateWidget(covariant _MapEmbedView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      setState(() => _loading = true); // a new place or route — loader again
      _controller.loadRequest(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          ColoredBox(
            color: context.nt.mist,
            child: const Center(child: NTripiRingLoader(size: 44)),
          ),
      ],
    );
  }
}
