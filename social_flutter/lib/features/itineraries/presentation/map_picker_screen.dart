// presentation/map_picker_screen.dart — Full-screen map for picking a location.
//
// The user taps anywhere on the map to place a pin. Tapping again moves it.
// Every selected position is reverse-geocoded (Nominatim) into a bottom info
// card; "Confirm Location" pops with the resulting PlaceSuggestion, which is
// then pre-filled in the stop form.
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
import 'package:social_flutter/shared/widgets/location_error.dart';

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
  // Reverse-geocoded info for a manually picked pin — feeds the info card and
  // is reused by Confirm. Its lat/lng always equal the pin's exact position.
  PlaceSuggestion? _resolvedPlace;
  bool _isResolving = false;
  Timer? _resolveDebounce;
  // Bumped on every new pick — a stale resolve must not overwrite the card.
  int _resolveEpoch = 0;
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
    _resolveDebounce?.cancel();
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
          // top inset clears the search overlay, bottom the place-info card;
          // maxZoom stops a lone nearby result from slamming the camera down
          padding: EdgeInsets.fromLTRB(
            48,
            140,
            48,
            _selectedLocation != null ? 220 : 120,
          ),
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
    _resolveDebounce?.cancel();
    _resolveEpoch++; // a pending resolve must not overwrite the suggestion
    setState(() {
      _selectedLocation = position;
      _searchedSuggestion = suggestion;
      _resolvedPlace = null;
      _isResolving = false;
      // Keep the query + result markers (Google-Maps-like session) — only
      // the list collapses; tapping the field reopens it.
      _listVisible = false;
    });
    _mapController.move(position, 16);
    FocusScope.of(context).unfocus();
  }

  /// Info for the position the pin currently sits on, if known yet.
  PlaceSuggestion? get _activePlace => _searchedSuggestion ?? _resolvedPlace;

  /// Reverse-geocodes a manually picked pin so the info card can show what
  /// was selected. The stored result keeps the pin's exact coordinates —
  /// Nominatim's own lat/lng points at the snapped nearest place, not the pin.
  void _resolvePlaceInfo(LatLng position) {
    _resolveDebounce?.cancel();
    final epoch = ++_resolveEpoch;
    setState(() {
      _resolvedPlace = null;
      _isResolving = true;
    });
    // 400ms debounce respects Nominatim's 1 req/s limit on rapid re-taps.
    _resolveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final suggestion = await ref
          .read(geocodingServiceProvider)
          .reverseGeocode(
            position.latitude,
            position.longitude,
            languageCode: ref.read(localeProvider).languageCode,
          );
      if (!mounted || epoch != _resolveEpoch) return;
      setState(() {
        _isResolving = false;
        // Empty name on failure — the card falls back to "Unnamed location".
        _resolvedPlace = PlaceSuggestion(
          displayName: suggestion?.displayName ?? '',
          address: suggestion?.address ?? '',
          lat: position.latitude,
          lng: position.longitude,
          category: suggestion?.category,
        );
      });
    });
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
      showLocationOutcomeSnackbar(context, ref, outcome);
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
      _resolvePlaceInfo(position);
    } else {
      showLocationOutcomeSnackbar(context, ref, outcome);
    }
  }

  Future<void> _confirmLocation() async {
    final selected = _selectedLocation;
    if (selected == null) return;

    // Pin still sits on a search result — return it as-is; a reverse-geocode
    // at the same point would only degrade the name Nominatim already gave us.
    if (_searchedSuggestion != null) {
      context.pop(_searchedSuggestion);
      return;
    }

    // The info card already resolved this exact pin — reuse it, no request.
    final resolved = _resolvedPlace;
    if (resolved != null &&
        resolved.lat == selected.latitude &&
        resolved.lng == selected.longitude) {
      context.pop(resolved);
      return;
    }

    setState(() => _isGeocoding = true);
    try {
      final suggestion = await ref
          .read(geocodingServiceProvider)
          .reverseGeocode(
            selected.latitude,
            selected.longitude,
            languageCode: ref.read(localeProvider).languageCode,
          );

      if (!mounted) return;
      // Always return the pin's exact coordinates — Nominatim's own lat/lng
      // points at the snapped nearest place, not where the user put the pin.
      // Empty name when unidentified so the user can fill it in manually.
      context.pop(
        PlaceSuggestion(
          displayName: suggestion?.displayName ?? '',
          address: suggestion?.address ?? '',
          lat: selected.latitude,
          lng: selected.longitude,
          category: suggestion?.category,
        ),
      );
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

  /// "food_court" → "Food court" — raw Nominatim OSM value, not localized.
  String _prettifyCategory(String raw) {
    final s = raw.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Bottom card with everything known about the selected position — name,
  /// category, address, exact coordinates — plus the Confirm button.
  Widget _buildPlaceInfoCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;
    final place = _activePlace;
    final coords =
        '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
        '${_selectedLocation!.longitude.toStringAsFixed(6)}';

    return Material(
      color: nt.surface,
      elevation: 2,
      shadowColor: NtripiBrand.backdrop.withValues(alpha: 0.26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: nt.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isResolving)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(),
              )
            else if (place != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      place.displayName.isNotEmpty
                          ? place.displayName
                          : l10n.mapUnnamedPlace,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: nt.bark,
                      ),
                    ),
                  ),
                  if (place.category != null)
                    Container(
                      margin: const EdgeInsetsDirectional.only(start: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: nt.sand,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _prettifyCategory(place.category!),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: nt.forest,
                        ),
                      ),
                    ),
                ],
              ),
              if (place.address.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    place.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: nt.text2),
                  ),
                ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Icon(Icons.my_location, size: 13, color: nt.text2),
                const SizedBox(width: 5),
                Text(
                  coords,
                  // signed decimals render garbled in RTL locales
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 12, color: nt.text2),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isGeocoding ? null : _confirmLocation,
                icon:
                    _isGeocoding
                        ? const NTripiRingLoader(size: 18)
                        : const Icon(Icons.check),
                label: Text(l10n.mapConfirmLocation),
              ),
            ),
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
                _resolvePlaceInfo(latLng);
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
                      width: 40,
                      height: 40,
                      // pin tip (glyph bottom) sits exactly on the point
                      alignment: Alignment.topCenter,
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

          // Location FABs stacked above the place-info card in one column so
          // the card's variable height never overlaps them.
          PositionedDirectional(
            start: 16,
            end: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Use-my-location — drops the pin at the device position.
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FloatingActionButton.small(
                    // no default FAB hero tag — avoids flights against other FABs
                    heroTag: null,
                    tooltip: AppLocalizations.of(context)!.mapUseMyLocation,
                    onPressed:
                        (_isLocating || _isCapturing) ? null : _useMyLocation,
                    child:
                        _isCapturing
                            ? const NTripiRingLoader(size: 18)
                            : const Icon(Icons.add_location_alt),
                  ),
                ),
                const SizedBox(height: 8),
                // Recenter — moves the camera to the device position only.
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: AppLocalizations.of(context)!.mapMyLocation,
                    onPressed:
                        (_isLocating || _isCapturing) ? null : _goToMyLocation,
                    child:
                        _isLocating
                            ? const NTripiRingLoader(size: 18)
                            : const Icon(Icons.my_location),
                  ),
                ),
                if (_selectedLocation != null) ...[
                  const SizedBox(height: 12),
                  _buildPlaceInfoCard(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
