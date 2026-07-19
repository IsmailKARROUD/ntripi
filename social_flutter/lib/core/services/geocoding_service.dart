// core/services/geocoding_service.dart — Nominatim (OpenStreetMap) geocoding.
//
// Legal note:
//   All coordinates returned by this service come from Nominatim, which is
//   powered by OpenStreetMap data licensed under ODbL.
//   ODbL explicitly permits storing and using derived data (lat/lng coordinates)
//   as long as attribution is maintained in the UI ("© OpenStreetMap contributors").
//   This is fully compliant with OpenStreetMap's terms of use.
//
// Nominatim ToS:
//   - Max 1 request/second on the public instance.
//   - Must send a descriptive User-Agent header.
//   - The UI debounces search calls to stay within rate limits.
//   - See: https://operations.osmfoundation.org/policies/nominatim/

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// A single place suggestion returned by Nominatim search or reverse geocoding.
///
/// [displayName] is a short human-readable label (e.g. "Eiffel Tower").
/// [address] is the full formatted address string.
/// [lat] / [lng] are OSM-sourced coordinates — legal to store (ODbL).
/// [category] is Nominatim's raw OSM type (e.g. "cafe", "hotel"), if any.
class PlaceSuggestion {
  final String displayName;
  final String address;
  final double lat;
  final double lng;
  final String? category;

  const PlaceSuggestion({
    required this.displayName,
    required this.address,
    required this.lat,
    required this.lng,
    this.category,
  });
}

/// Service that wraps the Nominatim HTTP API.
///
/// This class uses its own Dio instance — separate from the app's auth-
/// intercepted Dio — because Nominatim is a third-party public API and
/// does not require the app's Bearer token.
class GeocodingService {
  final Dio _dio;

  static const _baseUrl = 'https://nominatim.openstreetmap.org';

  GeocodingService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ) {
    // Required by Nominatim ToS — every request must carry a descriptive
    // User-Agent so the OSM team can identify and contact abusive clients.
    _dio.options.headers['User-Agent'] = 'Ntripi/0.1 (ntripi-app)';
  }

  /// Search for places matching [query].
  ///
  /// Returns up to 5 suggestions. Called on every keystroke but the UI
  /// debounces at 400ms to respect Nominatim's 1 req/s rate limit.
  ///
  /// [languageCode] (e.g. 'ar'/'fr'/'en') is forwarded as Nominatim's
  /// `accept-language`, which localizes the returned `display_name`.
  ///
  /// [near] biases the search toward that point (usually the device position):
  /// Nominatim prefers matches inside a ~50 km viewbox around it, and the
  /// returned suggestions are sorted nearest-first.
  ///
  /// [boxSw]/[boxNe] override the near-derived viewbox with explicit corners
  /// (the map picker passes its visible bounds). With [bounded] true the box
  /// becomes a hard filter — only places inside it are returned.
  ///
  /// Nothing is stored at this point — results are displayed as suggestions
  /// only. Coordinates are only persisted when the user confirms a selection
  /// (see StopFormScreen).
  Future<List<PlaceSuggestion>> search(
    String query, {
    String? languageCode,
    LatLng? near,
    LatLng? boxSw,
    LatLng? boxNe,
    bool bounded = false,
  }) async {
    if (query.trim().isEmpty) return [];

    final response = await _dio.get<List<dynamic>>(
      '/search',
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': 5,
        'addressdetails': 1,
        // accept-language localizes Nominatim's display_name to the app language.
        if (languageCode != null) 'accept-language': languageCode,
        // Nominatim viewbox order is lon1,lat1,lon2,lat2.
        if (boxSw != null && boxNe != null)
          'viewbox':
              '${boxSw.longitude},${boxSw.latitude},'
              '${boxNe.longitude},${boxNe.latitude}'
        // viewbox without bounded=1 is a soft preference, not a filter —
        // nearby matches rank higher but famous far-away ones still appear.
        else if (near != null)
          'viewbox':
              '${near.longitude - 0.5},${near.latitude - 0.5},'
              '${near.longitude + 0.5},${near.latitude + 0.5}',
        // bounded=1 turns the viewbox into a hard filter (area-only search).
        if (bounded) 'bounded': 1,
      },
    );

    final results = response.data ?? [];
    final suggestions =
        results
            .cast<Map<String, dynamic>>()
            .map((result) => _parseSuggestion(result))
            .toList();

    if (near != null) {
      // Nominatim ranks by importance, not distance — re-sort nearest-first.
      const distance = Distance();
      suggestions.sort(
        (a, b) => distance
            .as(LengthUnit.Meter, near, LatLng(a.lat, a.lng))
            .compareTo(
              distance.as(LengthUnit.Meter, near, LatLng(b.lat, b.lng)),
            ),
      );
    }
    return suggestions;
  }

  /// Reverse geocode a coordinate pair to a [PlaceSuggestion].
  ///
  /// Called when the user drops a pin on the MapPickerScreen.
  /// [languageCode] localizes the resolved `display_name` (see [search]).
  /// Returns null if Nominatim cannot identify the location.
  Future<PlaceSuggestion?> reverseGeocode(
    double lat,
    double lng, {
    String? languageCode,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'json',
          // accept-language localizes Nominatim's display_name to the app language.
          if (languageCode != null) 'accept-language': languageCode,
        },
      );

      final data = response.data;
      if (data == null || data.containsKey('error')) return null;

      return _parseSuggestion(data);
    } on DioException {
      return null;
    }
  }

  /// Parse a Nominatim JSON result object into a [PlaceSuggestion].
  PlaceSuggestion _parseSuggestion(Map<String, dynamic> result) {
    final fullName = result['display_name'] as String? ?? '';
    // Use the first segment (before the first comma) as a short display name.
    final shortName = fullName.split(',').first.trim();

    // OSM's building=yes tag surfaces as type "yes" — meaningless to users.
    var category = result['type'] as String?;
    if (category != null && (category.isEmpty || category == 'yes')) {
      category = null;
    }

    return PlaceSuggestion(
      displayName: shortName.isNotEmpty ? shortName : fullName,
      address: fullName,
      lat: double.parse(result['lat'] as String),
      lng: double.parse(result['lon'] as String),
      category: category,
    );
  }
}

/// Riverpod provider for the GeocodingService singleton.
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return GeocodingService();
});
