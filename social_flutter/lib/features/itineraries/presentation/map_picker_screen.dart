// presentation/map_picker_screen.dart — Full-screen map for picking a location.
//
// The user taps anywhere on the map to place a pin. Tapping again moves it.
// "Confirm Location" reverse-geocodes the pin via Nominatim and pops with
// the resulting PlaceSuggestion, which is then pre-filled in the stop form.
//
// OSM attribution is displayed as required by the ODbL license.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/core/services/location_service.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
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
  final _searchController = TextEditingController();
  Timer? _debounce;
  // Last query actually sent to Nominatim — gates the "no results" card so it
  // can't flash while a newer keystroke's debounce is still pending.
  String _submittedQuery = '';
  // Suggestion the pin currently sits on; Confirm returns it directly instead
  // of reverse-geocoding (keeps the exact searched name/address). Cleared by
  // any manual re-pick (map tap, use-my-location).
  PlaceSuggestion? _searchedSuggestion;
  LatLng? _selectedLocation;
  LatLng? _deviceLocation;
  bool _isGeocoding = false;
  bool _isLocating = false;
  bool _isCapturing = false;
  // Suggestion list collapses after a selection or a map pan; the numbered
  // result markers stay on the map (they live in the provider until cleared).
  bool _listVisible = true;
  // "Search this area" pill — offered after a user gesture moves the map
  // while a search session is active.
  bool _showSearchArea = false;

  // Default center: Paris, France — a reasonable fallback for a travel app.
  static const _defaultCenter = LatLng(48.8566, 2.3522);

  // Captured in initState — using ref inside dispose throws in Riverpod 3.
  late final PlaceSearchNotifier _searchNotifier;

  @override
  void initState() {
    super.initState();
    _searchNotifier = ref.read(mapPlaceSearchProvider.notifier);
    if (widget.deviceLat != null && widget.deviceLng != null) {
      _deviceLocation = LatLng(widget.deviceLat!, widget.deviceLng!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    // Reset so a reopened picker doesn't show stale results — deferred to a
    // microtask because this screen's provider subscriptions are still open
    // during dispose; a synchronous state change would notify a defunct element.
    Future.microtask(_searchNotifier.clear);
    _mapController.dispose();
    super.dispose();
  }

  /// Point to rank suggestions around: the phone position when known, else
  /// the current map view — a denied-permission user still gets local results.
  LatLng? get _searchBias {
    if (_deviceLocation != null) return _deviceLocation;
    try {
      return _mapController.camera.center;
    } catch (_) {
      return null; // camera getter throws before the map's first frame
    }
  }

  void _onSearchChanged(String value) {
    // setState refreshes the clear-button visibility and reopens the list.
    setState(() => _listVisible = true);
    _debounce?.cancel();
    // 400ms debounce respects Nominatim's 1 req/s rate-limit policy.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _submittedQuery = value.trim();
      if (_submittedQuery.isEmpty && _showSearchArea) {
        setState(() => _showSearchArea = false);
      }
      _runAreaSearch();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _submittedQuery = '';
    _searchNotifier.clear();
    _showSearchArea = false;
    _listVisible = true;
    setState(() {});
  }

  /// Searches [_submittedQuery] within the displayed map area (the widening +
  /// nearest-anywhere fallback live in the notifier), then zooms out just
  /// enough to reveal results that landed beyond the current view.
  Future<void> _runAreaSearch() async {
    final query = _submittedQuery;
    if (query.isEmpty) {
      _searchNotifier.clear();
      return;
    }

    final MapCamera camera;
    try {
      camera = _mapController.camera;
    } catch (_) {
      // Before the map's first frame there is no viewport to bound — fall
      // back to the plain near-biased search.
      await _searchNotifier.search(query, near: _searchBias);
      return;
    }

    final bounds = camera.visibleBounds;
    await _searchNotifier.searchArea(
      query,
      sw: bounds.southWest,
      ne: bounds.northEast,
      center: camera.center,
    );

    // A newer query/clear owns the state now — don't move the camera for it.
    if (!mounted || _submittedQuery != query) return;
    final results = ref.read(mapPlaceSearchProvider).value ?? [];
    if (results.isEmpty) return;

    final visible = _mapController.camera.visibleBounds;
    final points = [for (final s in results) LatLng(s.lat, s.lng)];
    if (points.any((p) => !visible.contains(p))) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          // top inset clears the search overlay; maxZoom stops a lone nearby
          // result from slamming the camera down to street level
          padding: const EdgeInsets.fromLTRB(48, 140, 48, 120),
          maxZoom: 16,
        ),
      );
    }
  }

  /// "Search this area" pill — re-runs the active query in the new viewport.
  void _searchThisArea() {
    _debounce?.cancel();
    setState(() {
      _showSearchArea = false;
      _listVisible = true;
      // The field may hold newer text than the last debounce fire — trust it.
      _submittedQuery = _searchController.text.trim();
    });
    _runAreaSearch();
  }

  /// Jumps the map to a search result and drops the pin on it.
  void _selectSuggestion(PlaceSuggestion suggestion) {
    final position = LatLng(suggestion.lat, suggestion.lng);
    setState(() {
      _selectedLocation = position;
      _searchedSuggestion = suggestion;
      // Keep the query + result markers (Google-Maps-like session) — only
      // the list collapses; tapping the field reopens it.
      _listVisible = false;
    });
    _mapController.move(position, 16);
    FocusScope.of(context).unfocus();
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
        _searchedSuggestion = null; // pin no longer sits on a search result
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

    // Pin still sits on a search result — return it as-is; a reverse-geocode
    // at the same point would only degrade the name Nominatim already gave us.
    if (_searchedSuggestion != null) {
      context.pop(_searchedSuggestion);
      return;
    }

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

  /// Search field with, beneath it, the live suggestion list, a "no results"
  /// card, or the tap-to-place instruction banner when the search is idle.
  Widget _buildSearchOverlay(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final suggestionsAsync = ref.watch(mapPlaceSearchProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: l10n.searchPlaceHintText,
            filled: true,
            fillColor: nt.surface,
            prefixIcon: Icon(Icons.search_rounded, color: nt.forest),
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _clearSearch,
                    )
                    : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: nt.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: nt.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: nt.forest, width: 1.5),
            ),
          ),
          onChanged: _onSearchChanged,
          onTap: () {
            // Reopen a collapsed list when the user returns to the field.
            if (!_listVisible) setState(() => _listVisible = true);
          },
        ),
        suggestionsAsync.when(
          // Refreshes ("search this area", widening loop) must show progress,
          // not the stale list — Riverpod's default would skip loading.
          skipLoadingOnRefresh: false,
          loading:
              () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
          error: (_, _) => _buildInstructionBanner(context),
          data: (suggestions) {
            if (suggestions.isNotEmpty) {
              return _listVisible
                  ? _buildSuggestionsCard(suggestions, nt)
                  : const SizedBox.shrink();
            }
            // Only claim "no results" for the query we actually searched —
            // while a newer keystroke's debounce is pending, stay quiet.
            if (_submittedQuery.isNotEmpty &&
                _submittedQuery == _searchController.text.trim()) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.mapSearchNoResults,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              );
            }
            if (_searchController.text.trim().isEmpty) {
              return _buildInstructionBanner(context);
            }
            return const SizedBox.shrink();
          },
        ),
        if (_showSearchArea)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: nt.surface,
              elevation: 2,
              shadowColor: NtripiBrand.backdrop.withValues(alpha: 0.26),
              shape: StadiumBorder(side: BorderSide(color: nt.border)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _searchThisArea,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 16, color: nt.forest),
                      const SizedBox(width: 6),
                      Text(
                        l10n.mapSearchThisArea,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: nt.bark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInstructionBanner(BuildContext context) {
    return Card(
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
    );
  }

  Widget _buildSuggestionsCard(
    List<PlaceSuggestion> suggestions,
    NtripiColors nt,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      // Tiles live in a Material (not a color-decorated Container) so ListTile
      // background/ink paint on it — a colored intermediate box would hide
      // them (Flutter debug assert in list_tile.dart).
      child: Material(
        color: nt.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: nt.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < suggestions.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 52),
              ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: nt.sand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.location_on_rounded,
                    size: 18,
                    color: nt.forest,
                  ),
                ),
                title: Text(
                  suggestions[i].displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
                // Full address, unabbreviated — it's what disambiguates
                // same-named places.
                subtitle: Text(
                  suggestions[i].address,
                  style: TextStyle(fontSize: 11, color: nt.text2),
                ),
                onTap: () => _selectSuggestion(suggestions[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod keeps the previous value during a refresh, so the numbered
    // markers persist while a "search this area" round trip is in flight.
    final searchResults =
        ref.watch(mapPlaceSearchProvider).value ?? const <PlaceSuggestion>[];
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
              // Fires every gesture frame — only setState on an actual change.
              // hasGesture excludes our own move/fitCamera calls.
              onPositionChanged: (_, hasGesture) {
                if (!hasGesture || _submittedQuery.isEmpty) return;
                if (_showSearchArea && !_listVisible) return;
                setState(() {
                  _showSearchArea = true;
                  _listVisible = false;
                });
              },
              onTap: (_, latLng) {
                setState(() {
                  _selectedLocation = latLng;
                  _searchedSuggestion = null; // manual pick overrides search
                  _listVisible = false;
                });
                FocusScope.of(context).unfocus();
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

              // Numbered search-result badges — tapping one selects it
              // exactly like tapping its list row.
              if (searchResults.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < searchResults.length; i++)
                      Marker(
                        point: LatLng(
                          searchResults[i].lat,
                          searchResults[i].lng,
                        ),
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _selectSuggestion(searchResults[i]),
                          child: Container(
                            decoration: BoxDecoration(
                              // light palette — OSM tiles stay light in dark mode
                              color: NtripiColors.light.forest,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: NtripiBrand.chrome,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 4,
                                  color: NtripiBrand.backdrop.withValues(
                                    alpha: 0.26,
                                  ),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: NtripiBrand.chrome,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
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

          // Search bar + suggestions (or the instruction banner when idle)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildSearchOverlay(context),
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
