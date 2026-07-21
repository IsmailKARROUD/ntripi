import 'package:flutter/widgets.dart';

/// Non-web builds never render this — the card only reaches [MapEmbedWebView]
/// when `kIsWeb` is true (mobile uses webview_flutter instead). It exists purely
/// so the conditional export in map_embed_web_view.dart compiles off the web.
class MapEmbedWebView extends StatelessWidget {
  final String embedUrl;

  const MapEmbedWebView({super.key, required this.embedUrl});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
