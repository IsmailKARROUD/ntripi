// data/google_maps_links.dart — reading a Google Maps link's own text.
//
// String parsing only: nothing here fetches a link. The stop form imports this,
// never link_preview_service.dart, so pasting a link can never fetch Google's
// page. What a link's text yields is read when a Google surface draws the stop
// (the trip's route map, Open in Google Maps) and never stored as coordinates —
// coordinates in a Google link are Google's content.

// The check below mirrors the server's validators/map_link.py rule for rule;
// that file says why each one exists. Both are held to one sample list,
// test/support/map_link_samples.json — add a case there, never to one side.
const _mapsHosts = {
  'maps.app.goo.gl',
  'goo.gl',
  'google.com',
  'www.google.com',
  'maps.google.com',
};
// Controls, spaces of every kind, zero-width and bidi characters, the BOM and
// the backslash a browser reads as a slash. An explicit class, not \s, so the
// two languages refuse exactly the same characters.
final _unsafe = RegExp(
  r'[\u0000- \u007f-\u009f   -‏ - '
  r' -⁯　﻿\\]',
);
// Only ASCII blanks are trimmed — the same set the server strips.
final _edgeBlanks = RegExp(r'^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$');
final _badEscape = RegExp(r'%(?![0-9A-Fa-f]{2})');
final _asciiEscape = RegExp(r'%([0-7][0-9A-Fa-f])');
final _linkParts = RegExp(
  r'^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$',
  dotAll: true,
);
final _shortLinkPath = RegExp(r'^/[A-Za-z0-9_-]+/?$');
final _gooGlPath = RegExp(r'^/maps/[A-Za-z0-9_-]+/?$');
final _embeddedAddress = RegExp(
  r'[a-z][a-z0-9+.-]*://|//|\\'
  r'|(?<![a-z0-9_])(?:https?|javascript|vbscript|data|file|ftp):'
  r'|(?<![a-z0-9])www\.',
  caseSensitive: false,
);

/// %XX escapes of ASCII characters decoded until stable (three rounds at most).
/// Not `Uri.decodeComponent`: it throws on bytes that are not UTF-8, and
/// `Uri.parse` resolves the very dot segments this check must see.
String _decodeAsciiEscapes(String text) {
  var current = text;
  for (var round = 0; round < 3; round++) {
    final decoded = current.replaceAllMapped(
      _asciiEscape,
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
    if (decoded == current) break;
    current = decoded;
  }
  return current;
}

/// Mirror of the server's check (validators/map_link.py `is_google_maps_link`):
/// only the link shapes Google Maps itself produces pass — never Google's
/// redirect pages (`maps.google.com/url?q=…`), a `../` path, a userinfo or a
/// web address hidden in the query. The server stays the authority for what
/// gets stored; this validates the form's link field and gates the stop page's
/// preview fetch and its "Open in Google Maps".
bool isGoogleMapsUrl(String url) {
  final link = url.replaceAll(_edgeBlanks, '');
  if (link.isEmpty || _unsafe.hasMatch(link) || _badEscape.hasMatch(link)) {
    return false;
  }
  final parts = _linkParts.firstMatch(link);
  if (parts == null) return false;
  final scheme = parts[1]!.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  // The whole authority must be a bare host: userinfo or a port never matches.
  final host = parts[2]!.toLowerCase();
  if (!_mapsHosts.contains(host)) return false;

  final path = parts[3]!;
  final bool shapeOk;
  if (host == 'maps.app.goo.gl') {
    shapeOk = _shortLinkPath.hasMatch(path);
  } else if (host == 'goo.gl') {
    shapeOk = _gooGlPath.hasMatch(path);
  } else {
    // The first segment is exactly "maps" — not /url, /amp, /mapsXYZ.
    shapeOk = path == '/maps' ||
        path.startsWith('/maps/') ||
        (host == 'maps.google.com' && (path.isEmpty || path == '/'));
  }
  if (!shapeOk) return false;

  // Escaped slashes are legal inside a place link's data= (…!16s%2Fg%2F…);
  // a dot segment or a backslash once decoded is not.
  final decodedPath = _decodeAsciiEscapes(path);
  if (decodedPath.contains(r'\') ||
      decodedPath.split('/').any((s) => s == '.' || s == '..')) {
    return false;
  }
  for (final part in [parts[4], parts[5]]) {
    if (part != null &&
        part.isNotEmpty &&
        _embeddedAddress.hasMatch(_decodeAsciiEscapes(part))) {
      return false;
    }
  }
  return true;
}

/// Coordinate patterns Google Maps embeds in its URLs, most-precise first: the
/// place-data pin (!3d!4d), an explicit query/ll param, then the viewport
/// center (@lat,lng) as a last resort. Read by the stop page's preview (on the
/// *resolved* URL) and by the trip's route (on the stored link's text) — never
/// to store coordinates.
final _mapCoordPatterns = <RegExp>[
  RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
  RegExp(
    r'[?&](?:query|q|ll|destination|center)=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
  ),
  RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
];

/// Extracts a lat/lng pair from a Google Maps URL, or null when none is embedded
/// (e.g. a bare short link). Out-of-range matches are skipped.
(double, double)? extractMapCoords(String url) {
  for (final re in _mapCoordPatterns) {
    final m = re.firstMatch(url);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null) continue;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
    return (lat, lng);
  }
  return null;
}

/// Google place IDs as they appear in a Maps URL: an explicit `place_id:`/
/// `place_id=` param, or the `!1s` data field when it holds a `ChIJ…` ID. Only
/// the `ChIJ…` namespace is usable — the hex `!1s0x…:0x…` feature ID that most
/// long URLs carry is a *different* identifier the Embed API does not accept.
final _placeIdPatterns = <RegExp>[
  RegExp(r'place_id[:=]([A-Za-z0-9_-]{15,})'),
  RegExp(r'!1s(ChIJ[A-Za-z0-9_-]+)'),
];

/// Extracts a Google place ID from a Maps URL, or null when none is embedded.
/// Preferred over coords for the embed: `q=place_id:…` renders a named place
/// card, where a bare `lat,lng` renders only a pin. Short links carry no place
/// ID (the code is opaque until Google redirects), so they return null here.
String? extractPlaceId(String url) {
  for (final re in _placeIdPatterns) {
    final id = re.firstMatch(url)?.group(1);
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

