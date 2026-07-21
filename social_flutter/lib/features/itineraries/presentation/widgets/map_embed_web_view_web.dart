// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

/// Web renders the Google Maps Embed API directly as a browser `<iframe>` — no
/// webview_flutter (it has no web backend here). A real browser sends the page
/// origin as the `Referer`, so a website-restricted key is accepted when the
/// origin is on its allowlist (add `localhost:<port>` for local `flutter run`,
/// `ntripi.app` for the deployed build).
class MapEmbedWebView extends StatefulWidget {
  final String embedUrl;

  const MapEmbedWebView({super.key, required this.embedUrl});

  @override
  State<MapEmbedWebView> createState() => _MapEmbedWebViewState();
}

class _MapEmbedWebViewState extends State<MapEmbedWebView> {
  // registerViewFactory throws if the same viewType is registered twice, so key
  // it by URL and register each once across the app's lifetime.
  static final Set<String> _registered = <String>{};
  // Per-view load flags keyed by viewType so the once-registered factory can
  // flip the right widget's loader off when its iframe finishes loading.
  static final Map<String, ValueNotifier<bool>> _loaded = {};

  late final String _viewType;
  final ValueNotifier<bool> _isLoaded = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _viewType = 'gmaps-embed-${widget.embedUrl.hashCode}';
    _loaded[_viewType] = _isLoaded;
    if (_registered.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int _) {
          final iframe = html.IFrameElement()
            ..src = widget.embedUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          // Hide the Ntripi loader once the map iframe paints.
          iframe.onLoad.listen((_) => _loaded[_viewType]?.value = true);
          return iframe;
        },
      );
    }
  }

  @override
  void dispose() {
    _loaded.remove(_viewType);
    _isLoaded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        ValueListenableBuilder<bool>(
          valueListenable: _isLoaded,
          builder: (context, loaded, _) => loaded
              ? const SizedBox.shrink()
              : ColoredBox(
                  color: context.nt.mist,
                  child: const Center(child: NTripiRingLoader(size: 44)),
                ),
        ),
      ],
    );
  }
}
