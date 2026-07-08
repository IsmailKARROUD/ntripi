// presentation/map_picker_screen.dart — Full-screen map for picking a location.
//
// The user taps anywhere on the map to place a pin. Tapping again moves it.
// "Confirm Location" reverse-geocodes the pin via Nominatim and pops with
// the resulting PlaceSuggestion, which is then pre-filled in the stop form.
//
// OSM attribution is displayed as required by the ODbL license.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class MapPickerScreen extends ConsumerStatefulWidget {
  /// Optional initial coordinates to center the map on.
  final double? initialLat;
  final double? initialLng;

  const MapPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
  });

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  LatLng? _selectedLocation;
  bool _isGeocoding = false;

  // Default center: Paris, France — a reasonable fallback for a travel app.
  static const _defaultCenter = LatLng(48.8566, 2.3522);

  LatLng get _initialCenter {
    if (widget.initialLat != null && widget.initialLng != null) {
      return LatLng(widget.initialLat!, widget.initialLng!);
    }
    return _defaultCenter;
  }

  Future<void> _confirmLocation() async {
    if (_selectedLocation == null) return;

    setState(() => _isGeocoding = true);
    try {
      final suggestion = await ref.read(geocodingServiceProvider).reverseGeocode(
            _selectedLocation!.latitude,
            _selectedLocation!.longitude,
            languageCode: ref.read(localeProvider).languageCode,
          );

      if (!mounted) return;
      // If Nominatim couldn't identify the location, still return coordinates
      // with an empty name so the user can fill it in manually.
      final result = suggestion ??
          PlaceSuggestion(
            displayName: '',
            address: '',
            lat: _selectedLocation!.latitude,
            lng: _selectedLocation!.longitude,
          );
      context.pop(result);
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.mapPickLocationTitle),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: _isGeocoding ? null : _confirmLocation,
              child: _isGeocoding
                  ? const NTripiRingLoader(size: 20)
                  : Text(AppLocalizations.of(context)!.confirmButton),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 13,
              onTap: (_, latLng) {
                setState(() => _selectedLocation = latLng);
              },
            ),
            children: [
              // OSM tile layer — no API key required.
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ntripi.app',
              ),

              // Pin marker at the selected location.
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black26)],
                      ),
                    ),
                  ],
                ),

              // Required OSM attribution (ODbL license requirement).
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // Instruction banner
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _selectedLocation == null
                      ? AppLocalizations.of(context)!.mapTapToPlacePin
                      : AppLocalizations.of(context)!.mapTapToMovePin,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),

          // Confirm button at bottom (alternative to AppBar button)
          if (_selectedLocation != null)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: FilledButton.icon(
                onPressed: _isGeocoding ? null : _confirmLocation,
                icon: _isGeocoding
                    ? const NTripiRingLoader(size: 18)
                    : const Icon(Icons.check),
                label: Text(AppLocalizations.of(context)!.mapConfirmLocation),
              ),
            ),
        ],
      ),
    );
  }
}
