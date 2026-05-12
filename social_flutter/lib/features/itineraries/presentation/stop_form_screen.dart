// presentation/stop_form_screen.dart — Add or edit a stop in an itinerary.
//
// The screen has three logical sections:
//   1. Place search — debounced Nominatim search, pre-fills form fields.
//   2. Stop details — type, location, transit/place fields, cost, notes.
//   3. Annotations — visible only in edit mode (stop must exist first).
//
// Legal note: Nominatim results are shown as suggestions only. Coordinates
// are stored only when the user confirms a selection (ODbL compliance).

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/services/geocoding_service.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_form_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

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

class _StopFormScreenState extends ConsumerState<StopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _placeNameController = TextEditingController();
  final _placeAddressController = TextEditingController();
  int _durationDays = 0;
  int _durationHours = 0;
  int _durationMinutes = 0;
  final _costController = TextEditingController();
  final _notesController = TextEditingController();

  Timer? _debounce;
  bool _initialized = false;
  bool _saving = false;

  PlaceType? _placeType;
  double? _lat;
  double? _lng;
  bool _isFree = false;

  // Current stop (in edit mode)
  Stop? _existingStop;

  // Annotations collected before the stop is created (create mode only)
  final List<_PendingAnnotation> _pendingAnnotations = [];

  // false while showing read-only view; flips to true when owner taps edit
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = !widget.viewOnly;
    if (widget.isEditMode) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _initFromExistingStop());
    }
  }

  int? get _totalDurationMin {
    final total =
        _durationDays * 24 * 60 + _durationHours * 60 + _durationMinutes;
    return total > 0 ? total : null;
  }

  String get _durationLabel {
    final parts = <String>[
      if (_durationDays > 0) '${_durationDays}d',
      if (_durationHours > 0) '${_durationHours}h',
      if (_durationMinutes > 0)
        '${_durationMinutes.toString().padLeft(2, '0')}min',
    ];
    return parts.isEmpty ? 'Not set' : parts.join(' ');
  }

  Future<void> _showDurationPicker() async {
    int tempDays = _durationDays;
    int tempHours = _durationHours;
    int tempMinutes = _durationMinutes;

    final daysCtrl = FixedExtentScrollController(initialItem: tempDays);
    final hoursCtrl = FixedExtentScrollController(initialItem: tempHours);
    final minsCtrl = FixedExtentScrollController(initialItem: tempMinutes);

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    Text(
                      'Time to spend',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _durationDays = tempDays;
                          _durationHours = tempHours;
                          _durationMinutes = tempMinutes;
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: daysCtrl,
                        itemExtent: 44,
                        onSelectedItemChanged: (i) => tempDays = i,
                        children: List.generate(
                          366,
                          (i) => Center(child: Text('$i d')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: hoursCtrl,
                        itemExtent: 44,
                        onSelectedItemChanged: (i) => tempHours = i,
                        children: List.generate(
                          24,
                          (i) => Center(child: Text('$i h')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: minsCtrl,
                        itemExtent: 44,
                        onSelectedItemChanged: (i) => tempMinutes = i,
                        children: List.generate(
                          60,
                          (i) => Center(
                            child: Text('${i.toString().padLeft(2, '0')} min'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    daysCtrl.dispose();
    hoursCtrl.dispose();
    minsCtrl.dispose();
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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _placeNameController.dispose();
    _placeAddressController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // 400ms debounce respects Nominatim's 1 request/second rate limit.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(placeSearchProvider.notifier).search(value);
    });
  }

  void _applySuggestion(PlaceSuggestion suggestion) {
    setState(() {
      _placeNameController.text = suggestion.displayName;
      _placeAddressController.text = suggestion.address;
      _lat = suggestion.lat;
      _lng = suggestion.lng;
    });
    _searchController.clear();
    ref.read(placeSearchProvider.notifier).clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickOnMap() async {
    final result = await context.push<PlaceSuggestion>(
      '/map-picker',
      extra: {'lat': _lat, 'lng': _lng},
    );
    if (result != null) {
      _applySuggestion(result);
    }
  }

  Stop? _findDuplicate() {
    if (widget.isEditMode) return null;
    final stops = ref
            .read(itineraryDetailProvider(widget.itineraryId))
            .valueOrNull
            ?.stops ??
        [];
    for (final s in stops) {
      if (_lat != null && _lng != null && s.lat != null && s.lng != null) {
        // Use epsilon ~11m to handle floating-point rounding from DB storage.
        const eps = 0.0001;
        if ((_lat! - s.lat!).abs() < eps && (_lng! - s.lng!).abs() < eps) {
          return s;
        }
      } else {
        final newName = _placeNameController.text.trim().toLowerCase();
        if (newName.isNotEmpty &&
            (s.placeName?.trim().toLowerCase() ?? '') == newName) return s;
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (!widget.isEditMode) {
      final duplicate = _findDuplicate();
      if (duplicate != null) {
        final stopLabel = duplicate.placeName ?? 'A stop';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Duplicate stop'),
            content: Text(
              '$stopLabel is already in this itinerary. Add it again anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Add anyway'),
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
        if (_placeAddressController.text.trim().isNotEmpty)
          'place_address': _placeAddressController.text.trim(),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        if (_placeType != null) 'place_type': _placeType!.name,
        if (_totalDurationMin != null) 'duration_min': _totalDurationMin,
        'cost': double.tryParse(_costController.text.trim()) ?? 0.0,
        'is_free': _isFree,
        if (_notesController.text.trim().isNotEmpty)
          'notes': _notesController.text.trim(),
      };

      final notifier =
          ref.read(itineraryDetailProvider(widget.itineraryId).notifier);

      if (widget.isEditMode) {
        await notifier.updateStop(widget.stopId!, data);
      } else {
        await notifier.addStop(data);
        // Submit any annotations queued before the stop existed.
        if (_pendingAnnotations.isNotEmpty) {
          final itinerary =
              ref.read(itineraryDetailProvider(widget.itineraryId)).value;
          final newStop = itinerary?.stops.lastOrNull;
          if (newStop != null) {
            for (final pending in _pendingAnnotations) {
              await notifier.addAnnotation(newStop.id, {
                'type': pending.type.name,
                'content': pending.content,
              });
            }
          }
        }
      }

      if (!mounted) return;
      context.pop();
    } on ItineraryStaleException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Itinerary updated elsewhere'),
          content: const Text(
            'This itinerary was edited from another device. '
            'Go back and reload to see the latest version.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (mounted) context.pop();
              },
              child: const Text('Go back'),
            ),
          ],
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Annotation helpers
  // ---------------------------------------------------------------------------

  Future<void> _showAnnotationDialog({Annotation? existing}) async {
    if (!mounted) return;
    final result = await showAnnotationFormDialog(
      context,
      initialContent: existing?.content,
      initialType: existing?.type,
      isEdit: existing != null,
    );
    if (result == null || !mounted) return;

    final notifier =
        ref.read(itineraryDetailProvider(widget.itineraryId).notifier);

    if (existing != null) {
      // Edit — only send changed fields; skip API call if nothing changed.
      final contentChanged = result.content != existing.content;
      final typeChanged = result.type != existing.type;
      if (!contentChanged && !typeChanged) return;
      try {
        await notifier.updateAnnotation(
          widget.stopId!,
          existing.id,
          content: contentChanged ? result.content : null,
          type: typeChanged ? result.type : null,
        );
      } on Exception catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e as dynamic))),
        );
      }
    } else if (widget.isEditMode) {
      // Create — stop already exists, send to API immediately.
      try {
        await notifier.addAnnotation(widget.stopId!, {
          'type': result.type.name,
          'content': result.content,
        });
        _initFromExistingStop();
      } on Exception catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e as dynamic))),
        );
      }
    } else {
      // Create — stop doesn't exist yet, queue locally until save.
      setState(() {
        _pendingAnnotations.add(
          _PendingAnnotation(result.type, result.content),
        );
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: 'Delete this stop?',
      message: 'This will remove the stop, its annotations, and any transit '
          'segments connecting it. The remaining stops will reorder.',
    );

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteStop(widget.stopId!);
      if (!mounted) return;
      context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _deleteAnnotation(String annotationId) async {
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: 'Delete annotation?',
      message: 'This annotation will be permanently removed.',
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool readOnly = widget.viewOnly && !_isEditing;
    final suggestionsAsync = ref.watch(placeSearchProvider);
    final duplicate = _findDuplicate();

    final currentUserId = ref.watch(myProfileProvider).valueOrNull?.id;
    final itineraryAsync = ref.watch(itineraryDetailProvider(widget.itineraryId));
    final isOwner = currentUserId != null &&
        itineraryAsync.valueOrNull?.userId == currentUserId;

    // In edit mode, keep local stop in sync when provider updates.
    if (widget.isEditMode && _initialized) {
      ref.listen(itineraryDetailProvider(widget.itineraryId), (_, next) {
        next.whenData((itinerary) {
          try {
            final stop =
                itinerary.stops.firstWhere((s) => s.id == widget.stopId);
            if (mounted) setState(() => _existingStop = stop);
          } catch (_) {}
        });
      });
    }

    String appBarTitle;
    if (readOnly) {
      appBarTitle = 'Stop Details';
    } else if (widget.isEditMode) {
      appBarTitle = 'Edit Stop';
    } else {
      appBarTitle = 'Add Stop';
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          if (readOnly && isOwner)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit stop',
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ----------------------------------------------------------------
                  // Section 1: Place search (hidden in view mode)
                  // ----------------------------------------------------------------
                  if (!readOnly) ...[
                    LabelWithHelp(
                      label: 'Search for a place',
                      helpTitle: 'Search a place',
                      helpMessage:
                          'Type a place, restaurant, or landmark name. Pick a result to autofill the place name, address, and coordinates below.',
                      labelStyle: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Eiffel Tower, Paris',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(placeSearchProvider.notifier).clear();
                                },
                              )
                            : null,
                      ),
                      onChanged: _onSearchChanged,
                    ),

                    // Suggestions list
                    suggestionsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (suggestions) {
                        if (suggestions.isEmpty) return const SizedBox.shrink();
                        return Card(
                          margin: const EdgeInsets.only(top: 4),
                          child: Column(
                            children: suggestions
                                .map(
                                  (s) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.place_outlined),
                                    title: Text(s.displayName, maxLines: 1),
                                    subtitle: Text(
                                      s.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onTap: () => _applySuggestion(s),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ----------------------------------------------------------------
                  // Section 2: Stop details
                  // ----------------------------------------------------------------
                  Text(
                    'Stop details',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),

                  // Place name
                  TextFormField(
                    controller: _placeNameController,
                    readOnly: readOnly,
                    decoration: const InputDecoration(
                      label: LabelWithHelp(
                        label: 'Place name',
                        helpTitle: 'Place name',
                        helpMessage:
                            'Name of the place, restaurant, landmark, or stop.',
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Place name is required'
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // Place address
                  TextFormField(
                    controller: _placeAddressController,
                    readOnly: readOnly,
                    decoration: const InputDecoration(
                      label: LabelWithHelp(
                        label: 'Address',
                        helpTitle: 'Address',
                        helpMessage:
                            'Street address or area description. Optional.',
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Coordinates display + map picker
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _lat != null && _lng != null
                              ? 'Lat: ${_lat!.toStringAsFixed(5)}, Lng: ${_lng!.toStringAsFixed(5)}'
                              : 'No location selected',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ),
                      const FieldHelpIcon(
                        helpTitle: 'Coordinates',
                        helpMessage:
                            'The map location for this stop. Tap "Pick on map" to set or adjust it.',
                      ),
                      if (!readOnly)
                        OutlinedButton.icon(
                          onPressed: _pickOnMap,
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Pick on map'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Duplicate warning — shown live in create mode
                  if (!widget.isEditMode && duplicate != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_outlined,
                              size: 16, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${duplicate.placeName ?? 'A stop'} is already in this itinerary.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Place type
                  if (readOnly)
                    InputDecorator(
                      decoration: const InputDecoration(
                        label: LabelWithHelp(
                          label: 'Place type',
                          helpTitle: 'Place type',
                          helpMessage:
                              'What kind of place this is (e.g. eat & drink, sleep, sight). Used for filtering and the map icon.',
                        ),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _placeType?.label ?? '—',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    DropdownButtonFormField<PlaceType>(
                      value: _placeType,
                      decoration: const InputDecoration(
                        label: LabelWithHelp(
                          label: 'Place type',
                          helpTitle: 'Place type',
                          helpMessage:
                              'What kind of place this is (e.g. eat & drink, sleep, sight). Used for filtering and the map icon.',
                        ),
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Select place type'),
                      isExpanded: true,
                      selectedItemBuilder: (context) => PlaceType.values
                          .map((t) => Align(
                                alignment: Alignment.centerLeft,
                                child: Text(t.label),
                              ))
                          .toList(),
                      items: PlaceType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(t.label),
                                  const SizedBox(height: 2),
                                  Text(
                                    t.hint,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _placeType = v),
                    ),
                  const SizedBox(height: 16),

                  // Duration — recommended time to spend
                  InkWell(
                    onTap: readOnly ? null : _showDurationPicker,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        label: const LabelWithHelp(
                          label: 'Recommended time to spend',
                          helpTitle: 'Time to spend',
                          helpMessage:
                              'Roughly how long you expect to stay here. Tap to set days, hours, and minutes.',
                        ),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.schedule_outlined),
                        suffixIcon: readOnly
                            ? null
                            : (_totalDurationMin != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => setState(() {
                                      _durationDays = 0;
                                      _durationHours = 0;
                                      _durationMinutes = 0;
                                    }),
                                  )
                                : const Icon(Icons.chevron_right)),
                      ),
                      child: Text(
                        _durationLabel,
                        style: TextStyle(
                          color: _totalDurationMin == null
                              ? Theme.of(context).hintColor
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Is free toggle
                  if (readOnly)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _isFree ? Icons.check_circle_outline : Icons.money_off_outlined,
                        color: _isFree ? Colors.green : null,
                      ),
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_isFree ? 'This stop is free' : 'This stop has a cost'),
                          const SizedBox(width: 2),
                          const FieldHelpIcon(
                            helpTitle: 'Free',
                            helpMessage:
                                'Toggle on if visiting this place costs nothing.',
                          ),
                        ],
                      ),
                    )
                  else
                    SwitchListTile(
                      title: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('This stop is free'),
                          SizedBox(width: 2),
                          FieldHelpIcon(
                            helpTitle: 'Free',
                            helpMessage:
                                'Toggle on if visiting this place costs nothing.',
                          ),
                        ],
                      ),
                      value: _isFree,
                      onChanged: (v) => setState(() => _isFree = v),
                      contentPadding: EdgeInsets.zero,
                    ),

                  // Cost field — hidden when is_free = true
                  if (!_isFree) ...[
                    TextFormField(
                      controller: _costController,
                      readOnly: readOnly,
                      decoration: const InputDecoration(
                        label: LabelWithHelp(
                          label: 'Cost',
                          helpTitle: 'Cost',
                          helpMessage:
                              "Approximate cost per person, in the itinerary's currency.",
                        ),
                        border: OutlineInputBorder(),
                        prefixText: '€ ',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        if (double.tryParse(v) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Thoughts — Markdown source with toolbar (edit) or rendered (readOnly).
                  MarkdownNotesEditor(
                    controller: _notesController,
                    readOnly: readOnly,
                    label: 'Thoughts',
                    helpTitle: 'Thoughts',
                    helpMessage:
                        'Your personal take on this stop — what to expect, what you loved, things to skip, opening tips. Use the toolbar to add bold, italic, headings, or bullet lists.',
                  ),
                  const SizedBox(height: 20),

                  // ----------------------------------------------------------------
                  // Section 3: Annotations
                  // ----------------------------------------------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      LabelWithHelp(
                        label: 'Annotations',
                        helpTitle: 'Annotations',
                        helpMessage:
                            'Short tagged notes (advice, caution, avoid, info) attached to this stop. Useful for warnings or tips.',
                        labelStyle: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (!readOnly)
                        TextButton.icon(
                          onPressed: () => _showAnnotationDialog(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.isEditMode) ...[
                    // Edit mode: show saved annotations from the existing stop.
                    if (_existingStop == null ||
                        _existingStop!.annotations.isEmpty)
                      Text(
                        'No annotations yet.',
                        style: TextStyle(color: Colors.grey.shade600),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _existingStop!.annotations
                            .map(
                              (a) => AnnotationChip(
                                annotation: a,
                                onEdit: readOnly
                                    ? null
                                    : () => _showAnnotationDialog(existing: a),
                                onDelete: readOnly
                                    ? null
                                    : () => _deleteAnnotation(a.id),
                              ),
                            )
                            .toList(),
                      ),
                  ] else ...[
                    // Create mode: show locally queued annotations.
                    if (_pendingAnnotations.isEmpty)
                      Text(
                        'No annotations yet.',
                        style: TextStyle(color: Colors.grey.shade600),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _pendingAnnotations
                            .map(
                              (p) => Chip(
                                avatar: Icon(
                                  _annotationIcons[p.type],
                                  size: 16,
                                  color: _annotationColors[p.type],
                                ),
                                label: Text(
                                  p.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _annotationColors[p.type],
                                  ),
                                ),
                                backgroundColor:
                                    _annotationColors[p.type]!.withOpacity(0.1),
                                side: BorderSide.none,
                                deleteIcon: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: _annotationColors[p.type],
                                ),
                                onDeleted: () => setState(
                                    () => _pendingAnnotations.remove(p)),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                  const SizedBox(height: 20),

                  // Save button — hidden in read-only view
                  if (!readOnly) ...[
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(widget.isEditMode ? 'Save Changes' : 'Add Stop'),
                    ),

                    // Delete stop — edit mode only
                    if (widget.isEditMode) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _confirmDelete,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text(
                          'Delete Stop',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _annotationColors = {
    AnnotationType.advice: Color(0xFF2E7D32),
    AnnotationType.caution: Color(0xFFE65100),
    AnnotationType.avoid: Color(0xFFC62828),
    AnnotationType.info: Color(0xFF1565C0),
  };

  static const _annotationIcons = {
    AnnotationType.advice: Icons.lightbulb_outline,
    AnnotationType.caution: Icons.warning_amber_outlined,
    AnnotationType.avoid: Icons.block,
    AnnotationType.info: Icons.info_outline,
  };
}

/// Annotation queued locally in create mode before the stop is saved.
class _PendingAnnotation {
  final AnnotationType type;
  final String content;
  const _PendingAnnotation(this.type, this.content);
}
