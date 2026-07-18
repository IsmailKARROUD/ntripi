// presentation/map_picker_screen.dart — Full-screen map for picking a location.
//
// The user taps anywhere on the map to place a pin. Tapping again moves it.
// "Confirm Location" reverse-geocodes the pin via Nominatim and pops with
// the resulting PlaceSuggestion, which is then pre-filled in the stop form.
//
// OSM attribution is displayed as required by the ODbL license.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/core/services/location_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/device_location_dot.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class MapPickerScreen extends ConsumerStatefulWidget {
  /// Optional initial coordinates to center the map on.
  final double? initialLat;
  final double? initialLng;

  /// Device position already fetched by the stop form, if any — shown as a
  /// blue dot immediately and used as center fallback.
  final double? deviceLat;
  final double? deviceLng;

  const MapPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.deviceLat,
    this.deviceLng,
  });

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  final _mapController = MapController();
  LatLng? _selectedLocation;
  LatLng? _deviceLocation;
  bool _isGeocoding = false;
  bool _isLocating = false;
  bool _isCapturing = false;

  // Default center: Paris, France — a reasonable fallback for a travel app.
  static const _defaultCenter = LatLng(48.8566, 2.3522);

  @override
  void initState() {
    super.initState();
    if (widget.deviceLat != null && widget.deviceLng != null) {
      _deviceLocation = LatLng(widget.deviceLat!, widget.deviceLng!);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng get _initialCenter {
    if (widget.initialLat != null && widget.initialLng != null) {
      return LatLng(widget.initialLat!, widget.initialLng!);
    }
    return _deviceLocation ?? _defaultCenter;
  }

  /// Centers the camera on the device position — never places the pin.
  Future<void> _goToMyLocation() async {
    setState(() => _isLocating = true);
    final outcome = await ref.read(locationServiceProvider).getCurrentLatLng();
    if (!mounted) return;
    setState(() => _isLocating = false);

    if (outcome case LocationSuccess(:final position)) {
      setState(() => _deviceLocation = position);
      _mapController.move(position, 16);
    } else {
      _showOutcomeError(outcome);
    }
  }

  /// Captures the device position as the selected pin — "I'm here right now".
  Future<void> _useMyLocation() async {
    setState(() => _isCapturing = true);
    final outcome = await ref.read(locationServiceProvider).getCurrentLatLng();
    if (!mounted) return;
    setState(() => _isCapturing = false);

    if (outcome case LocationSuccess(:final position)) {
      setState(() {
        _deviceLocation = position;
        _selectedLocation = position; // drop the pin where the user stands
      });
      _mapController.move(position, 16);
    } else {
      _showOutcomeError(outcome);
    }
  }

  /// Maps a non-success outcome to a snackbar. Permission/service failures get
  /// an action that opens the relevant OS settings page so the user can fix it.
  void _showOutcomeError(LocationOutcome outcome) {
    final l10n = AppLocalizations.of(context)!;
    final service = ref.read(locationServiceProvider);
    switch (outcome) {
      case LocationSuccess():
        return;
      case LocationServiceDisabled():
        _showLocationError(
          l10n.locationServiceDisabled,
          onOpenSettings: service.openLocationSettings,
        );
      case LocationPermissionDenied():
        _showLocationError(
          l10n.locationPermissionDenied,
          onOpenSettings: service.openAppSettings,
        );
      case LocationUnavailable():
        _showLocationError(l10n.locationUnavailable);
    }
  }

  void _showLocationError(String message, {VoidCallback? onOpenSettings}) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action:
              onOpenSettings == null
                  ? null
                  : SnackBarAction(
                    label: l10n.locationOpenSettings,
                    onPressed: onOpenSettings,
                  ),
        ),
      );
  }

  Future<void> _confirmLocation() async {
    if (_selectedLocation == null) return;

    setState(() => _isGeocoding = true);
    try {
      final suggestion = await ref
          .read(geocodingServiceProvider)
          .reverseGeocode(
            _selectedLocation!.latitude,
            _selectedLocation!.longitude,
            languageCode: ref.read(localeProvider).languageCode,
          );

      if (!mounted) return;
      // If Nominatim couldn't identify the location, still return coordinates
      // with an empty name so the user can fill it in manually.
      final result =
          suggestion ??
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
              child:
                  _isGeocoding
                      ? const NTripiRingLoader(size: 20)
                      : Text(AppLocalizations.of(context)!.confirmButton),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
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

              // Blue "you are here" dot — display-only, below the pin.
              if (_deviceLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _deviceLocation!,
                      width: 18,
                      height: 18,
                      child: const DeviceLocationDot(),
                    ),
                  ],
                ),

              // Pin marker at the selected location.
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      child: Icon(
                        Icons.location_pin,
                        // light-palette red — OSM tiles stay light in dark mode
                        color: NtripiColors.light.danger,
                        size: 40,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: NtripiBrand.backdrop.withValues(alpha: 0.26),
                          ),
                        ],
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

          // Use-my-location button — drops the pin at the device position.
          PositionedDirectional(
            end: 16,
            bottom: 152,
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: AppLocalizations.of(context)!.mapUseMyLocation,
              onPressed: (_isLocating || _isCapturing) ? null : _useMyLocation,
              child:
                  _isCapturing
                      ? const NTripiRingLoader(size: 18)
                      : const Icon(Icons.add_location_alt),
            ),
          ),

          // Recenter button — moves the camera to the device position only.
          PositionedDirectional(
            end: 16,
            bottom: 100,
            child: FloatingActionButton.small(
              // no default FAB hero tag — avoids flights against other FABs
              heroTag: null,
              tooltip: AppLocalizations.of(context)!.mapMyLocation,
              onPressed: (_isLocating || _isCapturing) ? null : _goToMyLocation,
              child:
                  _isLocating
                      ? const NTripiRingLoader(size: 18)
                      : const Icon(Icons.my_location),
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
                icon:
                    _isGeocoding
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
