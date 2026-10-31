// Platform-switched export for the web-only map iframe. Mobile gets the stub
// (never rendered — GoogleMapEmbed uses webview_flutter there); web gets the
// real HtmlElementView iframe. Same conditional-import shape as
// core/utils/apple_platform.dart.
export 'map_embed_web_view_stub.dart'
    if (dart.library.html) 'map_embed_web_view_web.dart';
