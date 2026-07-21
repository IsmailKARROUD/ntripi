// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// Web renders the Google Maps Embed API directly as a browser `<iframe>` — no
/// webview_flutter (it has no web backend here). A real browser sends the page
/// origin as the `Referer`, so a website-restricted key is accepted when the
/// origin is on its allowlist (add `localhost:<port>` for local `flutter run`,
/// `ntripi.app` for the deployed build).
class MapEmbedWebView extends StatelessWidget {
  final String embedUrl;

  const MapEmbedWebView({super.key, required this.embedUrl});

  // registerViewFactory throws if the same viewType is registered twice, so key
  // it by URL and register each once across the app's lifetime.
  static final Set<String> _registered = <String>{};

  @override
  Widget build(BuildContext context) {
    final viewType = 'gmaps-embed-${embedUrl.hashCode}';
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int _) => html.IFrameElement()
          ..src = embedUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%',
      );
    }
    return HtmlElementView(viewType: viewType);
  }
}
