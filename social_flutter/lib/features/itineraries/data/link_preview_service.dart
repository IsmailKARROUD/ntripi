// data/link_preview_service.dart — Client-side Open Graph unfurl for a stop's
// saved Google Maps link (the "WhatsApp/Telegram preview card").
//
// The stop page's preview only: the add/edit stop form never fetches a pasted
// link (that would be scraping Google as the user types) and must not import
// this file — it reads links through google_maps_links.dart, which only parses
// the string (test/stop_form_link_fetch_guard_test.dart).
//
// Legal / architectural posture (locked with the user):
//   * The PHONE fetches the pasted link directly and reads the publisher's own
//     Open Graph meta tags — user-initiated, allowlisted-host only. Nothing is
//     fetched or stored server-side, so there is no SSRF surface and no DB copy.
//   * On web a browser can't read Google's cross-origin response (CORS), so we
//     don't even try — fetch() short-circuits to null and the card degrades to a
//     plain "Opens in Google Maps" link.
//   * The resolved place name + coordinates are what the card feeds to a Google
//     Maps Embed webview (mobile only). No image is fetched or re-hosted here —
//     the unfurl exists only to turn a bare/short link into a name + coords.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/features/itineraries/data/google_maps_links.dart';

export 'package:ntripi/features/itineraries/data/google_maps_links.dart';

/// The unfurled Open Graph card data. Any field may be null when the page
/// omits that tag; a preview with neither a title nor coords is treated as "no
/// preview" (fetch returns null) so the caller shows the plain fallback.
class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  // Coords parsed from the *resolved* URL (post-redirect) — lets the form drop a
  // pin for a short link whose pasted form carried no coords, and feeds the
  // card's Maps Embed webview a precise query.
  final double? lat;
  final double? lng;

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.lat,
    this.lng,
  });

  // A preview is useful if it can seed the place name OR feed the embed a query.
  bool get hasContent => title != null || lat != null;
}

class LinkPreviewService {
  // A browser-like UA makes Google serve the crawler-friendly server-rendered
  // HTML (with og: tags) rather than a bare JS shell.
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Safari/537.36';

  /// Fetches and parses the Open Graph tags for [url]. Returns null on web
  /// (CORS), for a non-Google host, on any network/parse error, or when the
  /// page carries no usable og:title/og:image — the caller then shows the
  /// plain "Opens in Google Maps" fallback. Never throws.
  Future<LinkPreview?> fetch(String url) async {
    final trimmed = url.trim();
    // Web browsers block reading the cross-origin body — don't attempt it.
    if (kIsWeb) return null;
    if (!isGoogleMapsUrl(trimmed)) return null;

    try {
      final dio = Dio(
        BaseOptions(
          followRedirects: true, // resolve maps.app.goo.gl short links
          maxRedirects: 5,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          responseType: ResponseType.plain,
          // Accept 3xx/4xx without throwing so we can bail to null gracefully.
          validateStatus: (s) => s != null && s < 500,
          headers: const {
            'User-Agent': _userAgent,
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en',
          },
        ),
      );
      final resp = await dio.get<String>(trimmed);
      final body = resp.data;
      if (resp.statusCode != 200 || body == null || body.isEmpty) return null;
      return _parse(body, resp.realUri, trimmed);
    } catch (_) {
      // Any failure (timeout, DNS, consent interstitial, TLS…) → no preview.
      return null;
    }
  }

  LinkPreview? _parse(String html, Uri finalUri, String originalUrl) {
    // og: tags live in <head>; slicing there trims work and avoids matching
    // stray "content=" attributes deeper in the document.
    final headEnd = html.toLowerCase().indexOf('</head>');
    final head = headEnd == -1 ? html : html.substring(0, headEnd);

    final og = <String, String>{};
    for (final tag in _metaTag.allMatches(head)) {
      final raw = tag.group(0)!;
      final key = _attr(_propAttr, raw);
      if (key == null || !key.toLowerCase().startsWith('og:')) continue;
      final content = _attr(_contentAttr, raw);
      if (content == null || content.isEmpty) continue;
      og.putIfAbsent(key.toLowerCase(), () => _unescape(content));
    }

    // Google Maps is a JS SPA: its crawler HTML carries only a GENERIC
    // og:title ("Google Maps"), never the place name. The real name lives in
    // the resolved URL path (/maps/place/<NAME>/). Prefer that; fall back to a
    // non-generic og:title only (a future non-Maps host could have a real one).
    final pathName = _placeNameFromPath(finalUri.toString()) ??
        _placeNameFromPath(html);
    final ogTitle = og['og:title'];
    final title = pathName ??
        (ogTitle != null && !_isGenericMapsTitle(ogTitle) ? ogTitle : null);

    // The Maps og:description is boilerplate ("Find local businesses…"); only
    // surface a description when we actually used a genuine og:title.
    final description = (pathName == null && title != null)
        ? og['og:description']
        : null;

    // Coords from the resolved URL (a short link resolves here even though its
    // pasted form carried none) — the form uses these to drop a map pin. If the
    // short link served a JS interstitial (no HTTP redirect, so realUri stayed
    // the short URL), fall back to the canonical place URL embedded in the body.
    final bodyPlaceUrl = _firstPlaceUrl(html);
    final coords = extractMapCoords(finalUri.toString()) ??
        (bodyPlaceUrl != null ? extractMapCoords(bodyPlaceUrl) : null);

    final preview = LinkPreview(
      url: originalUrl,
      title: title,
      description: description,
      lat: coords?.$1,
      lng: coords?.$2,
    );
    return preview.hasContent ? preview : null;
  }

  static bool _isGenericMapsTitle(String t) =>
      t.trim().toLowerCase() == 'google maps';

  /// Pulls the human place name out of a `/maps/place/NAME/` segment in [text]
  /// (a resolved URL or the raw HTML body, which embeds the canonical place
  /// URL). Google encodes spaces as '+', so replace '+' BEFORE percent-decoding.
  static String? _placeNameFromPath(String text) {
    final m = _placePathPattern.firstMatch(text);
    if (m == null) return null;
    final raw = m.group(1)!;
    if (raw.isEmpty) return null;
    try {
      final name = Uri.decodeComponent(raw.replaceAll('+', ' ')).trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      // Malformed %-escape — fall back to the '+'-decoded form.
      final name = raw.replaceAll('+', ' ').trim();
      return name.isEmpty ? null : name;
    }
  }

  /// First /maps/place/... URL embedded in the body — used to recover coords
  /// when a short link served a JS interstitial (no HTTP redirect for realUri).
  static String? _firstPlaceUrl(String html) =>
      _placeUrlPattern.firstMatch(html)?.group(0);

  // /maps/place/<NAME>/ (or /maps/search/<QUERY>) — the name up to the next
  // '/', '?' or '#'. Matches both the requested URL and the body's canonical.
  static final _placePathPattern = RegExp(
    r'/maps/(?:place|search)/([^/?#]+)',
    caseSensitive: false,
  );
  static final _placeUrlPattern = RegExp(
    r'''https?://[^\s"'<>]*?/maps/place/[^\s"'<>]*''',
    caseSensitive: false,
  );

  // Each <meta …> tag; attributes then read individually so property-first and
  // content-first orderings both parse.
  static final _metaTag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final _propAttr = RegExp(
    r'''(?:property|name)\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final _contentAttr = RegExp(
    r'''content\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );

  static String? _attr(RegExp re, String tag) => re.firstMatch(tag)?.group(1);

  /// Minimal HTML-entity decode — enough for the handful that appear in og
  /// title/description text (ampersands, quotes, angle brackets).
  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

final linkPreviewServiceProvider = Provider<LinkPreviewService>(
  (ref) => LinkPreviewService(),
);

/// Per-URL unfurl. The family key doubles as the on-device metadata cache:
/// Riverpod keeps the resolved LinkPreview for the session, so re-showing the
/// same link (edit/re-open) doesn't re-hit the network.
final linkPreviewProvider = FutureProvider.family<LinkPreview?, String>(
  (ref, url) => ref.read(linkPreviewServiceProvider).fetch(url),
);
