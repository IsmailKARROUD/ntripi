// data/google_maps_links.dart — reading a Google Maps link's own text.
//
// String parsing only: nothing here fetches a link. The stop form imports this,
// never link_preview_service.dart, so pasting a link can never fetch Google's
// page. What a link's text yields is read when a Google surface draws the stop
// (the trip's route map, Open in Google Maps) and never stored as coordinates —
// coordinates in a Google link are Google's content.

/// Mirror of the backend allowlist (schemas/itinerary.py `validate_google_maps_url`).
/// The server stays the authority for what gets stored; this validates the
/// form's link field and gates the stop page's preview fetch, so no request is
/// ever made to a non-Google host. Only Google Maps hosts pass.
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

