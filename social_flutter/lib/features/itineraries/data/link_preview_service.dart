// data/link_preview_service.dart — Client-side Open Graph unfurl for a stop's
// saved Google Maps link (the "WhatsApp/Telegram preview card").
//
// Legal / architectural posture (locked with the user):
//   * The PHONE fetches the pasted link directly and reads the publisher's own
//     Open Graph meta tags — user-initiated, allowlisted-host only. Nothing is
//     fetched or stored server-side, so there is no SSRF surface and no DB copy.
//   * On web a browser can't read Google's cross-origin response (CORS), so we
//     don't even try — fetch() short-circuits to null and the card degrades to a
//     plain "Opens in Google Maps" link.
//   * The og:image is hotlinked (never re-hosted) and only transiently cached on
//     device via NtripiLinkPreviewCacheManager (short TTL) in the card widget.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mirror of the backend allowlist (schemas/itinerary.py `validate_google_maps_url`).
/// The server stays the authority for what gets stored; this gates the on-device
/// fetch so we never fire an outbound request at a non-Google host. Only Google
/// Maps hosts pass — every other link is rejected.
bool isGoogleMapsUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host == 'maps.google.com' || host == 'maps.app.goo.gl') return true;
  // Bare-domain hosts must scope to /maps so a generic google.com / goo.gl
  // link (search, mail, arbitrary short link) can't slip through.
  return (host == 'google.com' ||
          host == 'www.google.com' ||
          host == 'goo.gl') &&
      uri.path.startsWith('/maps');
}

/// The unfurled Open Graph card data. Any field may be null when the page
/// omits that tag; a preview with neither title nor image is treated as "no
/// preview" (fetch returns null) so the caller shows the plain fallback.
class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  bool get hasContent => title != null || imageUrl != null;
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

    String? image = og['og:image'];
    if (image != null) {
      // Resolve a rare relative og:image against the final (post-redirect) URL.
      final parsed = Uri.tryParse(image);
      if (parsed != null && !parsed.hasScheme) {
        image = finalUri.resolveUri(parsed).toString();
      }
    }

    final preview = LinkPreview(
      url: originalUrl,
      title: og['og:title'],
      description: og['og:description'],
      imageUrl: image,
    );
    return preview.hasContent ? preview : null;
  }

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
