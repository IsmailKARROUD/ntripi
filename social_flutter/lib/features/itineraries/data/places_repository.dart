// data/places_repository.dart — the stop form's Google place search, over the
// shared Dio client (and so the shared connection pool).
//
// Google is reached only through our server, which holds the key and each
// user's hourly budget (routers/places.py). The suggestions are Google's
// display text: shown while the user chooses, never stored — the autocomplete
// is a POST, so the HTTP cache never keeps it, and only the chosen place ID
// comes back to the server, on the stop write.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/domain/search_bias.dart';

/// Which Google place features the server has keys for.
class PlacesConfig {
  /// Places Autocomplete — the form's "Search on Google Maps".
  final bool googleSearch;

  /// The /embed map pages — every Google map in the app.
  final bool googleMaps;

  const PlacesConfig({required this.googleSearch, required this.googleMaps});

  static const disabled = PlacesConfig(googleSearch: false, googleMaps: false);

  factory PlacesConfig.fromJson(Map<String, dynamic> json) => PlacesConfig(
        googleSearch: json['google_search'] as bool? ?? false,
        googleMaps: json['google_maps'] as bool? ?? false,
      );
}

/// One Google suggestion, as the user sees it while choosing.
class GoogleSuggestion {
  final String placeId;
  final String mainText;
  final String? secondaryText;

  const GoogleSuggestion({
    required this.placeId,
    required this.mainText,
    this.secondaryText,
  });

  factory GoogleSuggestion.fromJson(Map<String, dynamic> json) =>
      GoogleSuggestion(
        placeId: json['place_id'] as String,
        mainText: json['main_text'] as String,
        secondaryText: json['secondary_text'] as String?,
      );
}

class PlacesRepository {
  final Dio _dio;

  const PlacesRepository(this._dio);

  Future<PlacesConfig> getConfig() async {
    final response =
        await _dio.get<Map<String, dynamic>>(kPlacesConfigEndpoint);
    final data = response.data;
    return data == null ? PlacesConfig.disabled : PlacesConfig.fromJson(data);
  }

  /// [bias] is already rounded where it is the device's; the server rounds
  /// every bias again before it reaches Google.
  Future<List<GoogleSuggestion>> autocomplete({
    required String input,
    required String language,
    BiasPoint? bias,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      kGooglePlaceAutocompleteEndpoint,
      data: {
        'input': input,
        'language': language,
        if (bias != null) 'bias': {'lat': bias.lat, 'lng': bias.lng},
      },
      cancelToken: cancelToken,
    );
    return ((response.data?['suggestions'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(GoogleSuggestion.fromJson)
        .toList();
  }
}

final placesRepositoryProvider = Provider<PlacesRepository>((ref) {
  return PlacesRepository(dio);
});
