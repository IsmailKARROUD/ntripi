// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

/// Web frames our own /embed page (GoogleEmbed) in a browser `<iframe>` — no
/// webview_flutter here. The page then frames Google, whose referrer check
/// sees this site. /embed is the one path our pages may frame
/// (EMBED_FRAME_ANCESTORS on the server: add a local dev origin there).
class MapEmbedWebView extends StatefulWidget {
  final String embedUrl;

  const MapEmbedWebView({super.key, required this.embedUrl});

  @override
  State<MapEmbedWebView> createState() => _MapEmbedWebViewState();
}

class _MapEmbedWebViewState extends State<MapEmbedWebView> {
  // One view type per widget, registered once (registerViewFactory throws on a
  // repeat); a new URL moves the same iframe, so swiping the route's
  // alternatives never piles up registrations.
  static int _nextId = 0;
  late final String _viewType = 'gmaps-embed-${_nextId++}';
  html.IFrameElement? _iframe;
  final ValueNotifier<bool> _isLoaded = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = html.IFrameElement()
        ..src = widget.embedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        // Display-only, as on phones: the tap belongs to the card around it.
        ..style.pointerEvents = 'none';
      // Hide the Ntripi loader once the map page paints.
      iframe.onLoad.listen((_) {
        if (mounted) _isLoaded.value = true;
      });
      return _iframe = iframe;
    });
  }

  @override
  void didUpdateWidget(covariant MapEmbedWebView old) {
    super.didUpdateWidget(old);
    if (old.embedUrl != widget.embedUrl) {
      _isLoaded.value = false;
      _iframe?.src = widget.embedUrl;
    }
  }

  @override
  void dispose() {
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
