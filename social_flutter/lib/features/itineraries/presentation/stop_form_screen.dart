// presentation/stop_form_screen.dart — Add or edit a stop in an itinerary.
//
// The screen has three logical sections:
//   1. Place search — OpenStreetMap on submit (never as you type: Nominatim's
//      policy), pre-fills the form; in the Google Maps segment Google Places is
//      the fallback (PlaceSearchBox).
//   2. Stop details — type, location, transit/place fields, cost, notes.
//   3. Annotations — visible only in edit mode (stop must exist first).
//
// Legal note: Nominatim results are shown as suggestions only. Coordinates
// are stored only when the user confirms a selection (ODbL compliance). From
// Google only a place ID and the user's own search text are ever stored, and a
// pasted link is never fetched here — this file must not import
// link_preview_service.dart (test/stop_form_link_fetch_guard_test.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard for the map-link paste button
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/core/services/location_service.dart';
import 'package:ntripi/features/itineraries/domain/annotation.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:ntripi/core/ui/destructive_actions.dart';
import 'package:ntripi/features/itineraries/presentation/annotation_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:ntripi/features/itineraries/data/google_embed_urls.dart';
import 'package:ntripi/features/itineraries/data/google_maps_links.dart';
import 'package:ntripi/features/itineraries/data/places_repository.dart';
import 'package:ntripi/features/itineraries/domain/map_point.dart';
import 'package:ntripi/features/itineraries/domain/search_bias.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/google_map_embed.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/place_search_box.dart';
import 'package:ntripi/features/itineraries/providers/places_providers.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/edit_lock.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/edit_lock_lost_notice.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/core/ui/toggle_feedback.dart';
import 'package:ntripi/core/utils/platform_utils.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/duration_picker_sheet.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';
import 'package:ntripi/shared/widgets/device_location_dot.dart';
import 'package:ntripi/shared/widgets/field_help.dart';
import 'package:ntripi/shared/widgets/loaders.dart';
import 'package:ntripi/shared/widgets/location_error.dart';
import 'package:ntripi/shared/widgets/moderation_hint.dart';
import 'package:ntripi/shared/widgets/offline_gate.dart';
import 'package:ntripi/shared/widgets/saving_overlay.dart';

class StopFormScreen extends ConsumerStatefulWidget {
  final String itineraryId;

  /// Null in create mode; the stop ID in edit mode.
  final String? stopId;

  /// Target track to add within (null = create a new track).
  final String? trackId;

  /// Stop after which to insert in the target track. Null = tail of track.
  final String? afterStopId;

  /// Track after which the new track should be placed (when trackId is null).
  final String? afterTrackId;

  /// Track before which the new track should be placed (when trackId is null).
  /// Must be passed alongside [afterTrackId] when inserting between two tracks.
  final String? beforeTrackId;

  /// When true the screen opens in read-only view; an edit button in the AppBar
  /// lets the owner switch to full edit mode without navigating away.
  final bool viewOnly;

  const StopFormScreen({
    super.key,
    required this.itineraryId,
    this.stopId,
    this.trackId,
    this.afterStopId,
    this.afterTrackId,
    this.beforeTrackId,
    this.viewOnly = false,
  });

  bool get isEditMode => stopId != null;

  @override
  ConsumerState<StopFormScreen> createState() => _StopFormScreenState();
}

// Distinguishes an explicit "None" tap from a dismissed (tap-outside/back)
// bottom sheet — both would otherwise pop with null.
const Object _clearPlaceTypeSentinel = Object();

// A stop's location is entered one of two ways, chosen by a toggle at the top of
// the form: `coordinates` (OSM search / lat-lng / pick-on-map, the default) or
// `google` — the Google Maps segment: a search that tries OSM first and Google
// Places after, and a pasted Google Maps link, for places OSM's gazetteer
// can't resolve. The mode governs which inputs are shown and which fields are
// authoritative on save.
enum _LocationMode { coordinates, google }

/// A Google place picked in this form: its ID and what the user typed to find
/// it — nothing Google returned.
typedef _GooglePick = ({String placeId, String query});

class _StopFormScreenState extends ConsumerState<StopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _placeNameController = TextEditingController();
  final _placeAddressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _mapUrlController = TextEditingController();
  final _previewMapController = MapController();
  int _durationDays = 0;
  int _durationHours = 0;
  int _durationMinutes = 0;
  final _costController = TextEditingController();
  final _notesController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  // Set when a save came back 409: the editing claim was taken over. NOTHING is
  // cleared or popped when this flips — the half-typed form is now the only
  // copy of the user's work, so it stays on screen with Save disabled.
  EditLock? _lockLostTo;
  bool _lockLost = false;
  bool _reclaiming = false;

  PlaceType? _placeType;
  double? _lat;
  double? _lng;
  bool _isFree = false;

  // Coordinates (default) vs the Google Maps segment. In edit/view mode it's
  // derived from the existing stop (see _initFromExistingStop).
  _LocationMode _locationMode = _LocationMode.coordinates;

  // The Google place this stop points to, when one is picked (or loaded).
  _GooglePick? _googlePick;
  // Google answered that the loaded place ID is gone: an editor searches again.
  bool _googlePlaceMissing = false;
  // Where _lat/_lng came from: an OSM pick, or typed / the device.
  PlaceSource? _coordsSource;
  // Any location action this session. Without one, a save leaves the stop's
  // place_source and Google fields to the server, so a place ID the yearly
  // refresh replaced meanwhile is never overwritten with the old one.
  bool _locationTouched = false;

  // Device position — preview-map centering + "you are here" dot only.
  // Never copied into _lat/_lng without an explicit user pick.
  LatLng? _deviceLocation;

  // In-flight guard for the preview map's use-my-location button.
  bool _isCapturingLocation = false;

  // Current stop (in edit mode)
  Stop? _existingStop;

  // Annotations collected before the stop is created (create mode only)
  final List<_PendingAnnotation> _pendingAnnotations = [];

  // Set once a create-mode Save has created the stop. If a queued annotation
  // then fails, the form stays open; Save again must finish THIS stop rather
  // than create a second one (and re-post the annotations that already landed).
  Stop? _createdStop;

  // false while showing read-only view; flips to true when owner taps edit
  bool _isEditing = false;

  // Create-mode only: collapses DETAILS/NOTES/ANNOTATIONS so first-time users
  // see only the mandatory place name + the auto-fillable location card.
  bool _showOptional = false;

  // Anchors the "tap Edit to make changes" popover onto the AppBar edit button.
  final GlobalKey _editButtonKey = GlobalKey();

  // Baseline of all user-editable fields, captured once the form is populated.
  // Compared against the live values to detect unsaved edits before leaving.
  List<Object?>? _initialSnapshot;

  @override
  void initState() {
    super.initState();
    _isEditing = !widget.viewOnly;
    if (widget.isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _initFromExistingStop(),
      );
    } else {
      _initialSnapshot = _snapshot();
    }
    // Skip in read-only view — don't fire a permission prompt for spectators;
    // the edit-pencil tap fetches instead when the owner starts editing.
    if (_isEditing) _fetchDeviceLocation();
  }

  /// Best-effort device fix for the preview map. Silent on failure — the map
  /// picker's my-location button is where errors surface as snackbars.
  Future<void> _fetchDeviceLocation() async {
    final outcome = await ref.read(locationServiceProvider).getCurrentLatLng();
    if (!mounted || outcome is! LocationSuccess) return;
    setState(() => _deviceLocation = outcome.position);
    // Center on the device only while nothing is picked — never fight a
    // user-chosen location.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lat != null || _lng != null) return;
      try {
        _previewMapController.move(outcome.position, 14);
      } catch (_) {}
    });
  }

  // _searchController is intentionally excluded — the Nominatim search box is
  // transient and not part of the saved stop.
  // Coordinate controllers stand in for _lat/_lng so invalid text also counts
  // as an unsaved edit.
  List<Object?> _snapshot() => [
    _placeNameController.text,
    _placeAddressController.text,
    _latController.text,
    _lngController.text,
    _mapUrlController.text,
    _locationMode,
    _googlePick,
    _placeType,
    _durationDays,
    _durationHours,
    _durationMinutes,
    _costController.text,
    _isFree,
    _notesController.text,
    _pendingAnnotations.length,
  ];

  bool get _isDirty {
    final base = _initialSnapshot;
    if (base == null) return false;
    final now = _snapshot();
    if (now.length != base.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (now[i] != base[i]) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final l10n = AppLocalizations.of(context)!;
    return confirmDestructiveAction(
      context: context,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discardButton,
      cancelLabel: l10n.keepEditingButton,
    );
  }

  int? get _totalDurationMin {
    final total =
        _durationDays * 24 * 60 + _durationHours * 60 + _durationMinutes;
    return total > 0 ? total : null;
  }

  String get _durationLabel {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[
      if (_durationDays > 0) '$_durationDays${l10n.daysLabel}',
      if (_durationHours > 0) '$_durationHours${l10n.hoursLabel}',
      if (_durationMinutes > 0)
        '${_durationMinutes.toString().padLeft(2, '0')}${l10n.minutesLabel}',
    ];
    return parts.isEmpty ? l10n.notSet : parts.join(' ');
  }

  Future<void> _showDurationPicker() async {
    final picked = await showDurationPickerSheet(
      context: context,
      title: AppLocalizations.of(context)!.timeToSpendModalTitle,
      days: _durationDays,
      hours: _durationHours,
      minutes: _durationMinutes,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _durationDays = picked.days;
      _durationHours = picked.hours;
      _durationMinutes = picked.minutes;
    });
  }

  void _initFromExistingStop() {
    if (_initialized) return;
    final itinerary =
        ref.read(itineraryDetailProvider(widget.itineraryId)).value;
    if (itinerary == null) return;

    Stop? found;
    try {
      found = itinerary.stops.firstWhere((s) => s.id == widget.stopId);
    } catch (_) {
      return;
    }

    setState(() {
      _existingStop = found;
      _placeNameController.text = found!.placeName ?? '';
      _placeAddressController.text = found.placeAddress ?? '';
      _lat = found.lat;
      _lng = found.lng;
      _latController.text = _formatCoord(found.lat);
      _lngController.text = _formatCoord(found.lng);
      _mapUrlController.text = found.mapUrl ?? '';
      // A Google place is one with an ID and no link (a link may carry an ID
      // of its own, read out of its text by the server).
      final placeId = found.googlePlaceId;
      _googlePick = placeId != null && (found.mapUrl ?? '').isEmpty
          ? (placeId: placeId, query: found.googlePlaceQuery ?? '')
          : null;
      _googlePlaceMissing = _googlePick != null && found.googlePlaceMissing;
      // The way back to a lost place starts from what found it last time.
      if (_googlePlaceMissing) _searchController.text = _googlePick!.query;
      _coordsSource = switch (found.placeSource) {
        PlaceSource.osm || PlaceSource.typed => found.placeSource,
        _ => null,
      };
      // A saved link or Google place opens the Google Maps segment.
      _locationMode =
          ((found.mapUrl ?? '').isNotEmpty || _googlePick != null)
              ? _LocationMode.google
              : _LocationMode.coordinates;
      _placeType = found.placeType;
      if (found.durationMin != null) {
        final total = found.durationMin!;
        _durationDays = total ~/ (24 * 60);
        _durationHours = (total % (24 * 60)) ~/ 60;
        _durationMinutes = total % 60;
      }
      _costController.text = found.cost.toStringAsFixed(2);
      _isFree = found.isFree;
      _notesController.text = found.notes ?? '';
      _initialized = true;
    });
    // Capture baseline only after fields are populated, so opening an existing
    // stop and leaving without changes does not trigger the discard dialog.
    _initialSnapshot = _snapshot();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _placeNameController.dispose();
    _placeAddressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _mapUrlController.dispose();
    _previewMapController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Where both searches look first: the trip's own stops, else the device.
  BiasPoint? _searchBias() {
    final itinerary =
        ref.read(itineraryDetailProvider(widget.itineraryId)).value;
    return searchBias(
      tracks: itinerary?.tracks ?? const [],
      trackId: widget.trackId ?? _existingStop?.trackId,
      afterTrackId: widget.afterTrackId,
      beforeTrackId: widget.beforeTrackId,
      editingStopId: widget.stopId,
      deviceLat: _deviceLocation?.latitude,
      deviceLng: _deviceLocation?.longitude,
    );
  }

  /// An OpenStreetMap pick (either segment, or the map picker). OSM's data is
  /// open, so it fills the address and the coordinates — and the name only if
  /// the user has not typed one: their title is what the trip shows.
  void _applySuggestion(PlaceSuggestion suggestion) {
    setState(() {
      if (_placeNameController.text.trim().isEmpty) {
        _placeNameController.text = suggestion.displayName;
      }
      _placeAddressController.text = suggestion.address;
      _lat = suggestion.lat;
      _lng = suggestion.lng;
      _latController.text = _formatCoord(suggestion.lat);
      _lngController.text = _formatCoord(suggestion.lng);
      // A picker pin whose reverse lookup found no address is just a point.
      _coordsSource = suggestion.address.trim().isEmpty
          ? PlaceSource.typed
          : PlaceSource.osm;
      _locationTouched = true;
      // The last pick wins over a Google place or a link in the same segment.
      _googlePick = null;
      _googlePlaceMissing = false;
      if (_locationMode == _LocationMode.google) _mapUrlController.clear();
    });
    _recenterPreview();
    _searchController.clear();
    ref.read(placeSearchProvider.notifier).clear();
    FocusScope.of(context).unfocus();
  }

  /// A Google pick keeps Google's place ID and the text the user typed —
  /// never the suggestion's name or address, and it never fills the name.
  void _applyGoogleSuggestion(GoogleSuggestion suggestion, String searchText) {
    setState(() {
      _googlePick = (placeId: suggestion.placeId, query: searchText.trim());
      _googlePlaceMissing = false;
      _locationTouched = true;
      _mapUrlController.clear();
      _placeAddressController.clear();
      _lat = null;
      _lng = null;
      _latController.clear();
      _lngController.clear();
      _coordsSource = null;
    });
    _searchController.clear();
    ref.read(placeSearchProvider.notifier).clear();
    FocusScope.of(context).unfocus();
  }

  /// "Change" on the picked Google place: back to the search, starting from
  /// the words that found it.
  void _changeGooglePlace() {
    final query = _googlePick?.query ?? '';
    setState(() {
      _googlePick = null;
      _googlePlaceMissing = false;
      _locationTouched = true;
      _searchController.text = query;
    });
  }

  /// ~0.1m precision is plenty for a stop; trailing zeros are noise in a form.
  String _formatCoord(double? v) {
    if (v == null) return '';
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// Mirrors the coordinate text fields into _lat/_lng so the preview map,
  /// duplicate check, and save payload stay live; partial or invalid input
  /// keeps them null until both fields parse and are in range.
  ///
  /// A pasted "lat, lng" pair (Google Maps' "copy coordinates" format) landing
  /// in one field is split across both — a comma or interior whitespace never
  /// occurs in normal single-value entry, so it marks a pasted pair.
  void _onCoordChanged(String value) {
    final pair = _extractCoordPair(value);
    if (pair != null) {
      _setCoordText(_latController, pair.$1);
      _setCoordText(_lngController, pair.$2);
    }
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    final valid =
        lat != null &&
        lng != null &&
        !lat.isNaN &&
        !lng.isNaN &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    setState(() {
      _lat = valid ? lat : null;
      _lng = valid ? lng : null;
      _coordsSource = PlaceSource.typed;
      _locationTouched = true;
    });
    if (valid) _recenterPreview();
  }

  /// Extracts a "lat, lng" pair from pasted text; null when it isn't a pair.
  ///
  /// The app's copy formats all separate the two coordinates with a space,
  /// optionally fused to a comma or dot: "50.85, 4.45" · "50.85. 4.45". The
  /// decimal separator inside a coordinate may itself be a comma (European
  /// locale, "50,85"). So a comma/dot delimits the pair only when a space
  /// follows it; any comma left inside a token is a decimal and becomes a dot.
  (String, String)? _extractCoordPair(String value) {
    final trimmed = value.trim();
    // Split on the inter-coordinate whitespace, swallowing a comma/dot fused to
    // it. The mandatory \s+ never occurs inside a single number, so plain
    // single-value typing is left untouched (no split).
    final parts = trimmed.split(RegExp(r'\s*[,.]?\s+'));
    if (parts.length == 2) {
      final lat = _asCoordText(parts[0]);
      final lng = _asCoordText(parts[1]);
      return (lat != null && lng != null) ? (lat, lng) : null;
    }
    // No whitespace: fall back to a comma between two dot-decimal numbers,
    // e.g. "50.857808,4.452149".
    final m = RegExp(r'^(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)$').firstMatch(trimmed);
    return m != null ? (m.group(1)!, m.group(2)!) : null;
  }

  /// Normalizes one split coordinate token to a parseable dot-decimal string,
  /// or null when it isn't a number. A remaining comma is a European decimal.
  String? _asCoordText(String token) {
    final s = token.trim().replaceAll(',', '.');
    return double.tryParse(s) != null ? s : null;
  }

  // Programmatic set (not user input) — does not re-trigger onChanged.
  void _setCoordText(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _recenterPreview() {
    // Post-frame: the preview map may only mount this frame, and moving an
    // unattached MapController throws. initialCenter covers the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lat == null || _lng == null) return;
      try {
        _previewMapController.move(LatLng(_lat!, _lng!), 14);
      } catch (_) {}
    });
  }

  /// A typed or pasted Google Maps link. Nothing is read out of it here and
  /// nothing is fetched: the link is stored as typed, and its coordinates —
  /// Google's — are never saved (the server drops any sent beside a link).
  /// setState refreshes the inline validator and the short-link hint.
  void _onMapUrlChanged(String value) {
    setState(() {
      _locationTouched = true;
      // The last action wins over a Google place picked in the same segment.
      if (value.trim().isNotEmpty) {
        _googlePick = null;
        _googlePlaceMissing = false;
      }
    });
  }

  /// A pasted link whose own text names no place — a maps.app.goo.gl share
  /// link — cannot be put on the trip's map (D18): the form says so.
  bool get _isUnplaceableLink {
    final url = _mapUrlController.text.trim();
    return isGoogleMapsUrl(url) &&
        extractPlaceId(url) == null &&
        extractMapCoords(url) == null;
  }

  /// Fills the map-link field from the clipboard. Trimmed on the way in so a
  /// copied link with stray whitespace still passes the Google-Maps allowlist.
  Future<void> _pasteMapUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return; // widget may have been popped during the async read
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _mapUrlController.text = text;
    // Move the caret to the end so the field doesn't scroll to the start.
    _mapUrlController.selection = TextSelection.collapsed(offset: text.length);
    _onMapUrlChanged(text); // extract coords + refresh validity
  }

  void _clearMapUrl() {
    _mapUrlController.clear();
    _onMapUrlChanged('');
  }

  /// Compact suffix action (paste/clear) for the map-link field — sized down
  /// from IconButton's 48px default so it fits the dense borderless row.
  Widget _mapLinkAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }

  /// Preview-map counterpart of the picker's use-my-location button: captures
  /// the device position into the coordinate fields (coords only — place
  /// name/address stay untouched, they come from search or the picker).
  Future<void> _useMyLocationInPreview() async {
    setState(() => _isCapturingLocation = true);
    final outcome = await ref.read(locationServiceProvider).getCurrentLatLng();
    if (!mounted) return;
    setState(() => _isCapturingLocation = false);

    if (outcome case LocationSuccess(:final position)) {
      setState(() {
        _deviceLocation = position;
        _lat = position.latitude;
        _lng = position.longitude;
        _coordsSource = PlaceSource.typed;
        _locationTouched = true;
        _setCoordText(_latController, _formatCoord(position.latitude));
        _setCoordText(_lngController, _formatCoord(position.longitude));
      });
      _recenterPreview();
    } else {
      showLocationOutcomeSnackbar(context, ref, outcome);
    }
  }

  Widget _buildCoordField(
    FocusNode focusNode, {
    required TextEditingController controller,
    required bool isLat,
    required bool readOnly,
    required bool showEditHint,
    required AppLocalizations l10n,
    required NtripiColors nt,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      onTap: showEditHint ? _showEditModeHint : null,
      // signed decimals ("-7.62") render garbled in RTL locales
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: '—',
      ),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: nt.bark,
      ),
      onChanged: _onCoordChanged,
      validator:
          (v) => _validateCoord(
            v,
            isLat: isLat,
            other: (isLat ? _lngController : _latController).text,
            l10n: l10n,
          ),
    );
  }

  String? _validateCoord(
    String? value, {
    required bool isLat,
    required String other,
    required AppLocalizations l10n,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      // A lone coordinate is meaningless — require the pair or nothing.
      return other.trim().isEmpty ? null : l10n.coordinatesPairRequiredError;
    }
    final parsed = double.tryParse(text);
    final limit = isLat ? 90 : 180;
    if (parsed == null || parsed.isNaN || parsed < -limit || parsed > limit) {
      return isLat ? l10n.invalidLatitudeError : l10n.invalidLongitudeError;
    }
    return null;
  }

  Future<void> _pickOnMap() async {
    final result = await context.push<PlaceSuggestion>(
      '/map-picker',
      extra: {
        'lat': _lat,
        'lng': _lng,
        'deviceLat': _deviceLocation?.latitude,
        'deviceLng': _deviceLocation?.longitude,
      },
    );
    if (result != null) {
      // Confirming the pre-placed pin untouched must not overwrite a possibly
      // hand-edited name/address with Nominatim's — the picker keeps exact
      // coords, so unchanged ones mean the user never moved the pin.
      if (result.lat == _lat && result.lng == _lng) return;
      _applySuggestion(result);
    }
  }

  Stop? _findDuplicate() {
    if (widget.isEditMode) return null;
    final stops =
        ref.read(itineraryDetailProvider(widget.itineraryId)).value?.stops ??
        [];
    final pick = _googlePick;
    for (final s in stops) {
      if (pick != null && s.googlePlaceId == pick.placeId) return s;
      if (_lat != null && _lng != null && s.lat != null && s.lng != null) {
        // Use epsilon ~11m to handle floating-point rounding from DB storage.
        const eps = 0.0001;
        if ((_lat! - s.lat!).abs() < eps && (_lng! - s.lng!).abs() < eps) {
          return s;
        }
      } else {
        final newName = _placeNameController.text.trim().toLowerCase();
        if (newName.isNotEmpty &&
            (s.placeName?.trim().toLowerCase() ?? '') == newName)
          return s;
      }
    }
    return null;
  }

  /// The location half of a save. The active segment is authoritative, and
  /// every location key it does not hold goes out as null, so switching
  /// persists — the backend's exclude_unset keeps an omitted key unchanged.
  Map<String, dynamic> _locationPayload() {
    final address = _placeAddressController.text.trim();
    final link = _mapUrlController.text.trim();
    final pick = _googlePick;
    final inGoogleSegment = _locationMode == _LocationMode.google;
    if (inGoogleSegment && pick != null) {
      return {
        'place_address': null,
        'lat': null,
        'lng': null,
        'map_url': null,
        // Only when picked this session: an untouched Google stop leaves its
        // ID to the server, which may have refreshed it meanwhile.
        if (_locationTouched) ...{
          'place_source': PlaceSource.google.name,
          'google_place_id': pick.placeId,
          'google_place_query': pick.query,
        },
      };
    }
    if (inGoogleSegment && link.isNotEmpty) {
      // Never with coordinates: those would be Google's. The server reads a
      // place ID out of the link's text itself.
      return {
        'place_address': null,
        'lat': null,
        'lng': null,
        'map_url': link,
        if (_locationTouched) 'place_source': PlaceSource.link.name,
      };
    }
    final source = _coordsSource;
    return {
      'place_address': address.isEmpty ? null : address,
      'lat': _lat,
      'lng': _lng,
      'map_url': null,
      // Coordinates, or nothing: no Google place stays on this stop.
      'google_place_id': null,
      'google_place_query': null,
      if (_locationTouched && _lat != null && _lng != null && source != null)
        'place_source': source.name,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (!widget.isEditMode && _createdStop == null) {
      final duplicate = _findDuplicate();
      if (duplicate != null) {
        final l10n = AppLocalizations.of(context)!;
        final stopLabel = duplicate.placeName ?? l10n.aStopFallback;
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(l10n.duplicateStopTitle),
                content: Text(l10n.duplicateStopMessage(stopLabel)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(l10n.addAnyway),
                  ),
                ],
              ),
        );
        if (confirmed != true || !mounted) return;
      }
    }

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        if (!widget.isEditMode) 'track_id': widget.trackId,
        if (!widget.isEditMode && widget.afterStopId != null)
          'after_stop_id': widget.afterStopId,
        if (!widget.isEditMode && widget.afterTrackId != null)
          'after_track_id': widget.afterTrackId,
        if (!widget.isEditMode && widget.beforeTrackId != null)
          'before_track_id': widget.beforeTrackId,
        if (_placeNameController.text.trim().isNotEmpty)
          'place_name': _placeNameController.text.trim(),
        ..._locationPayload(),
        // Always send place_type (even null) so clearing it persists — the
        // backend's exclude_unset means an omitted key leaves the old value.
        'place_type': _placeType?.name,
        if (_totalDurationMin != null) 'duration_min': _totalDurationMin,
        'cost': double.tryParse(_costController.text.trim()) ?? 0.0,
        'is_free': _isFree,
        if (_notesController.text.trim().isNotEmpty)
          'notes': _notesController.text.trim(),
      };

      final notifier = ref.read(
        itineraryDetailProvider(widget.itineraryId).notifier,
      );

      if (widget.isEditMode) {
        await notifier.updateStop(widget.stopId!, data);
      } else {
        final created = _createdStop;
        final Stop newStop;
        if (created == null) {
          // Use the created stop's real id — a top/mid insert is not last in
          // rank order, so guessing stops.lastOrNull attached annotations to a
          // pre-existing stop.
          newStop = await notifier.addStop(data);
          _createdStop = newStop;
        } else {
          // A retry after a failed annotation: the stop exists, so save any
          // field edits onto it. The placement keys belong to creation only —
          // on a PATCH, track_id means "move".
          newStop = created;
          await notifier.updateStop(newStop.id, {
            for (final entry in data.entries)
              if (!const {
                'track_id', 'after_stop_id', 'after_track_id', 'before_track_id',
              }.contains(entry.key))
                entry.key: entry.value,
          });
        }
        // Submit any annotations queued before the stop existed, dropping each
        // from the queue as it lands so a retry posts only what is left.
        for (final pending in List.of(_pendingAnnotations)) {
          await notifier.addAnnotation(newStop.id, {
            'type': pending.type.name,
            'content': pending.content,
          });
          if (mounted) setState(() => _pendingAnnotations.remove(pending));
        }
      }

      if (!mounted) return;
      context.pop();
    } on ItineraryStaleException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final l10n = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(l10n.itineraryUpdatedTitle),
            content: Text(l10n.itineraryUpdatedMessage),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (mounted) context.pop();
                },
                child: Text(l10n.goBack),
              ),
            ],
          );
        },
      );
    } on EditLockLostException catch (e) {
      // Deliberately not a snackbar and deliberately not a pop: the user needs
      // to still see why Save stopped working, and their text has to survive.
      ref
          .read(editLockProvider(widget.itineraryId).notifier)
          .markLost(e.holder);
      if (!mounted) return;
      setState(() {
        _lockLost = true;
        _lockLostTo = e.holder;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractErrorMessage(e, AppLocalizations.of(context)!)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Try to get the editing session back after a takeover.
  ///
  /// Succeeds once the other party releases or their claim decays — the server
  /// decides, and a refusal just leaves the notice up. Nothing about the form
  /// is touched either way.
  Future<void> _reclaimEditSession() async {
    setState(() => _reclaiming = true);
    bool reclaimed = false;
    try {
      reclaimed = await ref
          .read(editLockProvider(widget.itineraryId).notifier)
          .acquire();
    } catch (_) {
      // Offline or a server error: the notice stays, which is the truth.
    }
    if (!mounted) return;
    setState(() {
      _reclaiming = false;
      if (reclaimed) {
        _lockLost = false;
        _lockLostTo = null;
      }
    });
    if (!reclaimed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.editLockReclaimed)),
    );
  }

  // ---------------------------------------------------------------------------
  // Annotation helpers
  // ---------------------------------------------------------------------------

  Future<void> _showAnnotationDialog({Annotation? existing}) async {
    if (!mounted) return;
    final notifier = ref.read(
      itineraryDetailProvider(widget.itineraryId).notifier,
    );

    // API path (edit mode or stop already exists):
    // Pass onSaveAsync so the annotation screen shows a spinner and pops itself
    // only after the API call completes — user sees feedback before returning.
    if (existing != null || widget.isEditMode) {
      await showAnnotationScreen(
        context,
        isEdit: existing != null,
        initialContent: existing?.content,
        initialType: existing?.type,
        stopName:
            _placeNameController.text.trim().isNotEmpty
                ? _placeNameController.text.trim()
                : null,
        onSaveAsync: (result) async {
          if (existing != null) {
            final contentChanged = result.content != existing.content;
            final typeChanged = result.type != existing.type;
            if (!contentChanged && !typeChanged) return;
            await notifier.updateAnnotation(
              widget.stopId!,
              existing.id,
              content: contentChanged ? result.content : null,
              type: typeChanged ? result.type : null,
            );
          } else {
            // Add new annotation to an already-saved stop.
            await notifier.addAnnotation(widget.stopId!, {
              'type': result.type.name,
              'content': result.content,
            });
            if (mounted) _initFromExistingStop();
          }
        },
      );
      return;
    }

    // Create mode — stop not saved yet; queue annotation locally.
    // No API call → no spinner needed; screen pops with result normally.
    final result = await showAnnotationScreen(
      context,
      isEdit: false,
      stopName:
          _placeNameController.text.trim().isNotEmpty
              ? _placeNameController.text.trim()
              : null,
    );
    if (result == null || !mounted) return;
    setState(
      () => _pendingAnnotations.add(
        _PendingAnnotation(result.type, result.content),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.deleteStopTitle,
      message: l10n.deleteStopMessage,
    );

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteStop(widget.stopId!);
      if (!mounted) return;
      // Skip past the stop detail screen below us — it would reload the
      // just-deleted stop and show "stop not found". Go straight to itinerary.
      context.go('/itineraries/${widget.itineraryId}');
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            extractErrorMessage(e as dynamic, AppLocalizations.of(context)!),
          ),
        ),
      );
    }
  }

  void _showEditModeHint() {
    final ctx = _editButtonKey.currentContext;
    if (ctx == null) return;
    final l10n = AppLocalizations.of(ctx)!;
    showFieldHelp(
      ctx,
      title: l10n.viewOnlyTitle,
      message: l10n.viewOnlyMessage,
    );
  }

  Future<void> _deleteAnnotation(String annotationId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.deleteAnnotationTitle,
      message: l10n.deleteAnnotationStopMessage,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteAnnotation(widget.stopId!, annotationId);
      _initFromExistingStop();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            extractErrorMessage(e as dynamic, AppLocalizations.of(context)!),
          ),
        ),
      );
    }
  }

  /// What the Google Maps segment holds, on Google's own map: a Google place by
  /// its ID, or an OSM pick by its coordinates. A pasted link shows nothing —
  /// it is never fetched here.
  Widget _buildGoogleSegmentPlace(
    BuildContext context,
    NtripiColors nt,
    AppLocalizations l10n,
    bool readOnly,
  ) {
    final mapsOn = ref.watch(placesConfigProvider).value?.googleMaps ?? false;
    final language = GoogleEmbed.languageOf(context);
    final pick = _googlePick;
    if (pick != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: nt.surface,
            borderRadius: BorderRadius.circular(NtripiRadius.tile),
            border: Border.all(color: nt.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mapsOn && !_googlePlaceMissing)
                GoogleMapEmbed(
                  url: GoogleEmbed.point(
                      PlacePoint(pick.placeId, pick.query), language),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, size: 18, color: nt.forest),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.googleMapsPlaceLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: nt.bark,
                            ),
                          ),
                          if (pick.query.isNotEmpty)
                            Text(
                              l10n.googlePlaceSearchedAs(pick.query),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: nt.text2),
                            ),
                        ],
                      ),
                    ),
                    if (!readOnly)
                      TextButton(
                        onPressed: _changeGooglePlace,
                        child: Text(_googlePlaceMissing
                            ? l10n.googlePlaceSearchAgain
                            : l10n.googlePlaceChange),
                      ),
                  ],
                ),
              ),
              if (_googlePlaceMissing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SheetErrorRow(l10n.googlePlaceMissing),
                ),
            ],
          ),
        ),
      );
    }
    if (mapsOn &&
        _mapUrlController.text.trim().isEmpty &&
        _lat != null &&
        _lng != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NtripiRadius.tile),
          child: GoogleMapEmbed(
            url: GoogleEmbed.point(CoordPoint(_lat!, _lng!), language),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// Two-segment pill toggle choosing how the location is entered: coordinates
  /// (OSM search / lat-lng) or Google Maps (OSM first, then Google; or a
  /// pasted link). Only shown in create/edit —
  /// read-only view derives the visible section straight from the stop's data.
  Widget _buildModeToggle(
    BuildContext context,
    NtripiColors nt,
    AppLocalizations l10n,
  ) {
    // onPrimary, not white — dark mode's forest fill is a light green that needs
    // deep-green text (matches the app's FilledButton foreground).
    final onForest = Theme.of(context).colorScheme.onPrimary;

    Widget segment(_LocationMode mode, IconData icon, String label) {
      final selected = _locationMode == mode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap:
              selected
                  ? null
                  : () {
                    FocusScope.of(context).unfocus();
                    // Each segment searches afresh: OSM results from one must
                    // not offer themselves in the other.
                    _searchController.clear();
                    ref.read(placeSearchProvider.notifier).clear();
                    setState(() => _locationMode = mode);
                  },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? nt.forest : Colors.transparent,
              borderRadius: BorderRadius.circular(NtripiRadius.inset),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? onForest : nt.text2),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? onForest : nt.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: nt.surface,
          borderRadius: BorderRadius.circular(NtripiRadius.toggle),
          border: Border.all(color: nt.border),
        ),
        child: Row(
          children: [
            segment(
              _LocationMode.coordinates,
              Icons.place_rounded,
              l10n.locationModeCoordinates,
            ),
            segment(
              _LocationMode.google,
              Icons.map_outlined,
              l10n.locationModeGoogleMaps,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final bool readOnly = widget.viewOnly && !_isEditing;
    // Edit mode shows every field at once so users can jump straight to what
    // they need to change. Only collapse for first-time creation.
    final bool collapseOptional =
        !widget.isEditMode && !readOnly && !_showOptional;
    final duplicate = _findDuplicate();

    final currentUserId = ref.watch(myProfileProvider).value?.id;
    final itineraryAsync = ref.watch(
      itineraryDetailProvider(widget.itineraryId),
    );
    final isOwner =
        currentUserId != null && itineraryAsync.value?.userId == currentUserId;
    final bool showEditHint = readOnly && isOwner;

    // In edit mode, keep local stop in sync when provider updates.
    if (widget.isEditMode && _initialized) {
      ref.listen(itineraryDetailProvider(widget.itineraryId), (_, next) {
        next.whenData((itinerary) {
          try {
            final stop = itinerary.stops.firstWhere(
              (s) => s.id == widget.stopId,
            );
            if (mounted) setState(() => _existingStop = stop);
          } catch (_) {}
        });
      });
    }

    final l10n = AppLocalizations.of(context)!;
    final appBarTitle =
        readOnly
            ? l10n.stopDetailsView
            : widget.isEditMode
            ? l10n.editStopTitle
            : l10n.addStopTitle;

    return PopScope(
      // Block the back gesture/button while there are unsaved edits; the
      // callback then offers a discard confirmation.
      canPop: !_isDirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: SavingOverlay(
        saving: _saving,
        child: Scaffold(
          backgroundColor: nt.surface,
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
              ),
              child: Column(children: [
          SafeArea(
            bottom: false,
            child: EditorialTopBar(
            title: appBarTitle,
            actions: [
              if (readOnly && isOwner)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: EditPencilButton(
                      key: _editButtonKey,
                      icon: Icons.edit_outlined,
                      iconSize: 22,
                      tooltip: l10n.editStopTooltip,
                      onTap: () {
                        setState(() => _isEditing = true);
                        // deferred from initState for view-only openers
                        if (_deviceLocation == null) _fetchDeviceLocation();
                      },
                    ),
                  ),
                ),
              if (!readOnly)
                _saving
                    ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: NTripiRingLoader(size: 20),
                    )
                    : OfflineGate(
                      builder:
                          (online) => TextButton(
                            onPressed: (online && !_lockLost) ? _save : null,
                            child: Text(
                              l10n.save,
                              style: TextStyle(
                                color: online ? nt.forest : nt.text3,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                    ),
            ],
          ),
          ),
          const EditorialDivider(),
          Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8, bottom: 40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_lockLost)
                        EditLockLostNotice(
                          holder: _lockLostTo,
                          busy: _reclaiming,
                          onReclaim: _reclaimEditSession,
                          // Notes is the only field worth rescuing by hand; a
                          // place name is retyped in seconds.
                          copyText: _notesController.text,
                        ),

                      // ── Location-source toggle (Coordinates | Google Maps link) ──
                      if (!readOnly) _buildModeToggle(context, nt, l10n),

                      // ----------------------------------------------------------------
                      // Section 1: Place search (hidden in view). OSM on submit in
                      // both segments; Google as the fallback in the Google one.
                      // ----------------------------------------------------------------
                      if (!readOnly) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: LabelWithHelp(
                            label: l10n.searchForPlaceLabel,
                            helpTitle:
                                _locationMode == _LocationMode.google
                                    ? l10n.googleMapsSearchHelpTitle
                                    : l10n.searchAPlaceHelpTitle,
                            helpMessage:
                                _locationMode == _LocationMode.google
                                    ? l10n.googleMapsSearchHelpMessage
                                    : l10n.searchAPlaceHelpMessage,
                            labelStyle: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: PlaceSearchBox(
                            // A segment switch starts a fresh search box.
                            key: ValueKey(_locationMode),
                            controller: _searchController,
                            googleFallback:
                                _locationMode == _LocationMode.google,
                            language: GoogleEmbed.languageOf(context),
                            bias: _searchBias,
                            onOsmPick: _applySuggestion,
                            onGooglePick: _applyGoogleSuggestion,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_locationMode == _LocationMode.google)
                        _buildGoogleSegmentPlace(context, nt, l10n, readOnly),

                      // ── Place name + address ───────────────────────────────
                      SectionCard(
                          clipBehavior: Clip.antiAlias,
                          crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SFBorderlessField(
                            label: l10n.placeNameLabel.toUpperCase(),
                            childBuilder:
                                (focusNode) => TextFormField(
                                  controller: _placeNameController,
                                  focusNode: focusNode,
                                  readOnly: readOnly,
                                  onTap:
                                      showEditHint ? _showEditModeHint : null,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: '—',
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: nt.bark,
                                  ),
                                  validator:
                                      (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? l10n.placeNameRequired
                                              : null,
                                ),
                          ),
                          // Address is a coordinate-stop field; hidden in link mode.
                          if (_locationMode == _LocationMode.coordinates) ...[
                            const FieldDivider(),
                            _SFBorderlessField(
                              label: l10n.addressLabel.toUpperCase(),
                              childBuilder:
                                  (focusNode) => TextFormField(
                                    controller: _placeAddressController,
                                    focusNode: focusNode,
                                    readOnly: readOnly,
                                    onTap:
                                        showEditHint ? _showEditModeHint : null,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintText: '—',
                                    ),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: nt.bark,
                                    ),
                                  ),
                            ),
                          ],
                        ],
                      ),

                      // ── Location: coordinates + map picker + preview ───────
                      const SizedBox(height: 8),
                      SectionCard(
                          clipBehavior: Clip.antiAlias,
                          crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_locationMode == _LocationMode.coordinates)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _SFBorderlessField(
                                      label: l10n.latitudeLabel.toUpperCase(),
                                      childBuilder:
                                          (focusNode) => _buildCoordField(
                                            focusNode,
                                            controller: _latController,
                                            isLat: true,
                                            readOnly: readOnly,
                                            showEditHint: showEditHint,
                                            l10n: l10n,
                                            nt: nt,
                                          ),
                                    ),
                                  ),
                                  Container(width: 1, color: nt.border),
                                  Expanded(
                                    child: _SFBorderlessField(
                                      label: l10n.longitudeLabel.toUpperCase(),
                                      childBuilder:
                                          (focusNode) => _buildCoordField(
                                            focusNode,
                                            controller: _lngController,
                                            isLat: false,
                                            readOnly: readOnly,
                                            showEditHint: showEditHint,
                                            l10n: l10n,
                                            nt: nt,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Google Maps link — for places neither search finds.
                          // Stored as typed and never fetched; no coordinates
                          // are taken from it.
                          if (_locationMode == _LocationMode.google &&
                              (!readOnly ||
                                  _mapUrlController.text.trim().isNotEmpty))
                            _SFBorderlessField(
                              label: l10n.mapLinkLabel.toUpperCase(),
                              childBuilder:
                                  (focusNode) => TextFormField(
                                    controller: _mapUrlController,
                                    focusNode: focusNode,
                                    readOnly: readOnly,
                                    onTap:
                                        showEditHint ? _showEditModeHint : null,
                                    onChanged: _onMapUrlChanged,
                                    keyboardType: TextInputType.url,
                                    // Surface the allowlist rejection inline as
                                    // the user types/pastes — not only on save.
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintText: l10n.mapLinkHint,
                                      suffixIcon:
                                          readOnly
                                              ? null
                                              : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _mapLinkAction(
                                                    icon:
                                                        Icons
                                                            .content_paste_rounded,
                                                    tooltip: l10n.mapLinkPaste,
                                                    color: nt.forest,
                                                    onPressed: _pasteMapUrl,
                                                  ),
                                                  if (_mapUrlController
                                                      .text
                                                      .isNotEmpty)
                                                    _mapLinkAction(
                                                      icon: Icons.close_rounded,
                                                      tooltip: l10n.mapLinkClear,
                                                      color: nt.text2,
                                                      onPressed: _clearMapUrl,
                                                    ),
                                                ],
                                              ),
                                      // Keep the suffix tight against the field
                                      // (default 48px min would break isDense).
                                      suffixIconConstraints:
                                          const BoxConstraints(
                                            minWidth: 0,
                                            minHeight: 0,
                                          ),
                                    ),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: nt.bark,
                                    ),
                                    validator: (v) {
                                      final t = v?.trim() ?? '';
                                      if (t.isEmpty) return null;
                                      return isGoogleMapsUrl(t)
                                          ? null
                                          : l10n.mapLinkInvalid;
                                    },
                                  ),
                            ),
                          if (!readOnly &&
                              _locationMode == _LocationMode.coordinates) ...[
                            const FieldDivider(),
                            _SFPickerRow(
                              icon: Icons.map_rounded,
                              label: l10n.locationLabel.toUpperCase(),
                              value: l10n.mapPickLocationTitle,
                              onTap: _pickOnMap,
                            ),
                          ],
                          if (_locationMode == _LocationMode.coordinates &&
                              ((_lat != null && _lng != null) ||
                                  _deviceLocation != null))
                            SizedBox(
                              height: 160,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTap: readOnly ? null : _pickOnMap,
                                      child: FlutterMap(
                                        mapController: _previewMapController,
                                        options: MapOptions(
                                          // device fix stands in until a location is picked
                                          initialCenter:
                                              _lat != null && _lng != null
                                                  ? LatLng(_lat!, _lng!)
                                                  : _deviceLocation!,
                                          initialZoom: 14,
                                          interactionOptions:
                                              const InteractionOptions(
                                                flags: InteractiveFlag.none,
                                              ),
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate:
                                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                            userAgentPackageName:
                                                'com.ntripi.app',
                                            // silently discard tile errors (offline / test mode)
                                            errorTileCallback: (_, _, _) {},
                                          ),
                                          // Blue "you are here" dot — display-only.
                                          if (_deviceLocation != null)
                                            MarkerLayer(
                                              markers: [
                                                Marker(
                                                  point: _deviceLocation!,
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      const DeviceLocationDot(),
                                                ),
                                              ],
                                            ),
                                          if (_lat != null && _lng != null)
                                            MarkerLayer(
                                              markers: [
                                                Marker(
                                                  point: LatLng(_lat!, _lng!),
                                                  width: 36,
                                                  height: 36,
                                                  // pin tip (glyph bottom) sits on the point
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: Icon(
                                                    Icons.location_pin,
                                                    // light-palette red — OSM tiles stay light in dark mode
                                                    color:
                                                        NtripiColors
                                                            .light
                                                            .danger,
                                                    size: 36,
                                                    shadows: [
                                                      Shadow(
                                                        blurRadius: 4,
                                                        color: NtripiBrand
                                                            .backdrop
                                                            .withValues(
                                                              alpha: 0.26,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          // Required OSM attribution (ODbL license requirement).
                                          RichAttributionWidget(
                                            attributions: [
                                              TextSourceAttribution(
                                                'OpenStreetMap contributors',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Expand icon — explicit affordance that the
                                  // preview opens the full map picker.
                                  if (!readOnly)
                                    PositionedDirectional(
                                      top: 8,
                                      end: 8,
                                      child: Tooltip(
                                        message: l10n.mapPickLocationTitle,
                                        child: Material(
                                          color: nt.buttonTransparent,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: _pickOnMap,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Icon(
                                                Icons.open_in_full,
                                                size: 18,
                                                color: nt.overlayChrome,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Use-my-location — fills the coordinate
                                  // fields with the device position.
                                  // bottom-start: OSM attribution owns
                                  // bottom-right, the expand icon top-end.
                                  if (!readOnly)
                                    PositionedDirectional(
                                      bottom: 8,
                                      start: 8,
                                      child: Tooltip(
                                        message: l10n.mapUseMyLocation,
                                        child: Material(
                                          color: nt.buttonTransparent,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap:
                                                _isCapturingLocation
                                                    ? null
                                                    : _useMyLocationInPreview,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child:
                                                  _isCapturingLocation
                                                      ? const NTripiRingLoader(
                                                        size: 18,
                                                      )
                                                      : Icon(
                                                        Icons.add_location_alt,
                                                        size: 18,
                                                        color: nt.overlayChrome,
                                                      ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      // A short link names no place: it cannot go on the
                      // trip's map, and searching would put it there (D18).
                      if (_locationMode == _LocationMode.google &&
                          _isUnplaceableLink)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 16, color: nt.text2),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.mapLinkShortLinkHint,
                                  style: TextStyle(
                                      fontSize: 12, color: nt.text2),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── Duplicate warning ──────────────────────────────────
                      if (!widget.isEditMode && duplicate != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: nt.transitBg,
                            borderRadius: BorderRadius.circular(NtripiRadius.tile),
                            border: Border.all(color: nt.transitBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: nt.transitIcon,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.alreadyInItinerary(
                                    duplicate.placeName ?? l10n.aStopFallback,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: nt.transitText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── Optional fields toggle (create mode only) ──────────
                      if (!widget.isEditMode && !readOnly)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Align(
                            alignment: Alignment.center,
                            child: InkWell(
                              onTap:
                                  () => setState(
                                    () => _showOptional = !_showOptional,
                                  ),
                              borderRadius: BorderRadius.circular(NtripiRadius.tile),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showOptional
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 16,
                                      color: nt.forest,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _showOptional
                                          ? l10n.hideOptionalFields
                                          : l10n.showOptionalFields,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: nt.forest,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      if (!collapseOptional) ...[
                        // ── DETAILS ────────────────────────────────────────────
                        SectionLabel(label: l10n.detailsSection),
                        SectionCard(
                          clipBehavior: Clip.antiAlias,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Place type
                            _SFPickerRow(
                              icon: _placeType?.icon ?? Icons.category_rounded,
                              iconColor: _placeType?.color(nt) ?? nt.forest,
                              label: l10n.placeTypeLabel.toUpperCase(),
                              value: _placeType?.label(l10n) ?? '—',
                              onTap: readOnly ? null : _showPlaceTypePicker,
                            ),
                            const FieldDivider(),
                            // Duration
                            _SFPickerRow(
                              icon: Icons.schedule_rounded,
                              label: l10n.timeToSpendModalTitle.toUpperCase(),
                              value: _durationLabel,
                              onTap: readOnly ? null : _showDurationPicker,
                            ),
                            const FieldDivider(),
                            // Free toggle
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: nt.mist,
                                      borderRadius: BorderRadius.circular(NtripiRadius.icon),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.payments_rounded,
                                      size: 16,
                                      color: nt.forest,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l10n.costLabel.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: nt.text2,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        Text(
                                          l10n.stopIsFree,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: nt.bark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _isFree,
                                    // null while readOnly, so a disabled switch
                                    // stays silent without asking.
                                    onChanged: readOnly
                                        ? null
                                        : (v) {
                                            setState(() => _isFree = v);
                                            toggleFeedback(ref);
                                          },
                                    thumbColor: WidgetStateProperty.resolveWith((
                                      states,
                                    ) {
                                      if (states.contains(
                                        WidgetState.disabled,
                                      )) {
                                        // disabled-on: muted forest; disabled-off: grey
                                        return states.contains(
                                              WidgetState.selected,
                                            )
                                            ? nt.forest.withAlpha(160)
                                            : nt.text3;
                                      }
                                      return states.contains(
                                            WidgetState.selected,
                                          )
                                          ? nt.forest
                                          : nt.surface;
                                    }),
                                    trackColor: WidgetStateProperty.resolveWith(
                                      (states) {
                                        if (states.contains(
                                          WidgetState.disabled,
                                        )) {
                                          return states.contains(
                                                WidgetState.selected,
                                              )
                                              ? nt.mist.withAlpha(200)
                                              : nt.border;
                                        }
                                        return states.contains(
                                              WidgetState.selected,
                                            )
                                            ? nt.mist
                                            : nt.border;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isFree) ...[
                              const FieldDivider(),
                              _SFBorderlessField(
                                label: l10n.costLabel.toUpperCase(),
                                childBuilder:
                                    (focusNode) => TextFormField(
                                      controller: _costController,
                                      focusNode: focusNode,
                                      readOnly: readOnly,
                                      onTap:
                                          showEditHint
                                              ? _showEditModeHint
                                              : null,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                        hintText: l10n.stopCostHint,
                                        prefixText: '€ ',
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: nt.bark,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return null;
                                        if (double.tryParse(v) == null) {
                                          return l10n.enterValidNumber;
                                        }
                                        return null;
                                      },
                                    ),
                              ),
                            ],
                          ],
                        ),

                        // ── NOTES ─────────────────────────────────────────────
                        SectionLabel(label: l10n.notesLabel),
                        SectionCard(
                          clipBehavior: Clip.antiAlias,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              // Notes only — the place name/address fields stay
                              // unfiltered (real place names false-positive).
                              child: ModerationHint(
                                controller: _notesController,
                                child: MarkdownNotesEditor(
                                  controller: _notesController,
                                  readOnly: readOnly,
                                  label: l10n.thoughtsLabel,
                                  helpTitle: l10n.thoughtsLabel,
                                  helpMessage: l10n.thoughtsHelp,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── ANNOTATIONS ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            22,
                            14,
                            16,
                            6,
                          ),
                          child: Row(
                            children: [
                              Text(
                                l10n.annotationsSection.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: nt.text2,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const Spacer(),
                              if (!readOnly)
                                OfflineGate(
                                  builder:
                                      (online) => GestureDetector(
                                        onTap:
                                            online
                                                ? () => _showAnnotationDialog()
                                                : null,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.add_rounded,
                                              size: 14,
                                              color:
                                                  online ? nt.forest : nt.text3,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              l10n.addButton,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    online
                                                        ? nt.forest
                                                        : nt.text3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: _buildAnnotationsContent(
                            context,
                            readOnly,
                            l10n,
                          ),
                        ),
                      ],

                      // ── Delete (edit mode, non-readonly) ───────────────────
                      if (!readOnly && widget.isEditMode) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: OfflineGate(
                            builder:
                                (online) => OutlinedButton.icon(
                                  onPressed:
                                      (_saving || !online)
                                          ? null
                                          : _confirmDelete,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: nt.danger,
                                  ),
                                  label: Text(
                                    l10n.deleteStopButton,
                                    style: TextStyle(color: nt.danger),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: nt.danger),
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Place type picker bottom sheet ──────────────────────────────────────
  Future<void> _showPlaceTypePicker() async {
    final nt = context.nt;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    alignment: Alignment.center,
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: nt.text3.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(NtripiRadius.pill),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!.placeTypeLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: nt.text2,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children:
                          PlaceType.values.map((t) {
                            final l10n = AppLocalizations.of(context)!;
                            final selected = _placeType == t;
                            return ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: t.color(nt).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(NtripiRadius.icon),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  t.icon,
                                  size: 18,
                                  color: t.color(nt),
                                ),
                              ),
                              title: Text(
                                t.label(l10n),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: nt.bark,
                                ),
                              ),
                              subtitle: Text(
                                t.hint(l10n),
                                style: TextStyle(fontSize: 11, color: nt.text2),
                              ),
                              trailing:
                                  selected
                                      ? Icon(
                                        Icons.check_rounded,
                                        color: nt.forest,
                                        size: 18,
                                      )
                                      : null,
                              onTap: () => Navigator.pop(ctx, t),
                            );
                          }).toList(),
                    ),
                  ),
                  if (_placeType != null)
                    ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: nt.border,
                          borderRadius: BorderRadius.circular(NtripiRadius.icon),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: nt.text3,
                        ),
                      ),
                      title: Text(
                        AppLocalizations.of(context)!.noneOption,
                        style: TextStyle(color: nt.text2),
                      ),
                      onTap: () => Navigator.pop(ctx, _clearPlaceTypeSentinel),
                    ),
                ],
              ),
            ),
          ),
    );
    if (!mounted || picked == null) return;
    if (picked == _clearPlaceTypeSentinel) {
      setState(() => _placeType = null);
    } else {
      setState(() => _placeType = picked as PlaceType);
    }
  }

  // ── Annotations section content ──────────────────────────────────────────
  Widget _buildAnnotationsContent(
    BuildContext context,
    bool readOnly,
    AppLocalizations l10n,
  ) {
    if (widget.isEditMode) {
      final annos = _existingStop?.annotations ?? [];
      if (annos.isEmpty) {
        final nt = context.nt;
        return Text(
          l10n.noAnnotationsYet,
          style: TextStyle(color: nt.text3, fontSize: 13),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children:
            annos
                .map(
                  (a) => AnnotationChip(
                    annotation: a,
                    onEdit:
                        readOnly
                            ? null
                            : () => _showAnnotationDialog(existing: a),
                    onDelete: readOnly ? null : () => _deleteAnnotation(a.id),
                  ),
                )
                .toList(),
      );
    } else {
      if (_pendingAnnotations.isEmpty) {
        final nt = context.nt;
        return Text(
          l10n.noAnnotationsYet,
          style: TextStyle(color: nt.text3, fontSize: 13),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children:
            _pendingAnnotations
                .map(
                  (p) => AnnotationChip(
                    annotation: Annotation(
                      id: 'pending-${p.content.hashCode}',
                      stopId: '',
                      type: p.type,
                      content: p.content,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                    onDelete:
                        () => setState(() => _pendingAnnotations.remove(p)),
                  ),
                )
                .toList(),
      );
    }
  }
}

// ─── Stop-form editorial helpers ─────────────────────────────────────────────




class _SFBorderlessField extends StatefulWidget {
  final String label;
  final Widget Function(FocusNode focusNode) childBuilder;
  const _SFBorderlessField({required this.label, required this.childBuilder});

  @override
  State<_SFBorderlessField> createState() => _SFBorderlessFieldState();
}

class _SFBorderlessFieldState extends State<_SFBorderlessField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // opaque so taps on the label and on empty space inside the column
    // also focus the input — not just direct hits on the TextFormField
    behavior: HitTestBehavior.opaque,
    onTap: _focusNode.requestFocus,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.nt.text2,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          widget.childBuilder(_focusNode),
        ],
      ),
    ),
  );
}

class _SFPickerRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _SFPickerRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final tint = iconColor ?? nt.forest;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: nt.mist,
                borderRadius: BorderRadius.circular(NtripiRadius.icon),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: nt.text2,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: nt.bark,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: nt.text3),
          ],
        ),
      ),
    );
  }
}

/// Annotation queued locally in create mode before the stop is saved.
class _PendingAnnotation {
  final AnnotationType type;
  final String content;
  const _PendingAnnotation(this.type, this.content);
}
