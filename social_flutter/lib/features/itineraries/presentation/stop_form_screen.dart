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
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/presentation/annotation_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _initFromExistingStop());
    } else {
      _initialSnapshot = _snapshot();
    }
  }

  // _searchController is intentionally excluded — the Nominatim search box is
  // transient and not part of the saved stop.
  List<Object?> _snapshot() => [
        _placeNameController.text,
        _placeAddressController.text,
        _lat,
        _lng,
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
      if (_durationDays > 0) '${_durationDays}${l10n.daysLabel}',
      if (_durationHours > 0) '${_durationHours}${l10n.hoursLabel}',
      if (_durationMinutes > 0)
        '${_durationMinutes.toString().padLeft(2, '0')}${l10n.minutesLabel}',
    ];
    return parts.isEmpty ? l10n.notSet : parts.join(' ');
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
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    Text(
                      AppLocalizations.of(context)!.timeToSpendModalTitle,
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
                      child: Text(AppLocalizations.of(context)!.doneTooltip),
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
                          (i) => Center(child: Text('$i ${AppLocalizations.of(context)!.daysLabel}')),
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
                          (i) => Center(child: Text('$i ${AppLocalizations.of(context)!.hoursLabel}')),
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
                            child: Text('${i.toString().padLeft(2, '0')} ${AppLocalizations.of(context)!.minutesLabel}'),
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
    // Capture baseline only after fields are populated, so opening an existing
    // stop and leaving without changes does not trigger the discard dialog.
    _initialSnapshot = _snapshot();
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
            .value
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
        final l10n = AppLocalizations.of(context)!;
        final stopLabel = duplicate.placeName ?? l10n.aStopFallback;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
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
        if (_placeAddressController.text.trim().isNotEmpty)
          'place_address': _placeAddressController.text.trim(),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        // Always send place_type (even null) so clearing it persists — the
        // backend's exclude_unset means an omitted key leaves the old value.
        'place_type': _placeType?.name,
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
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
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
    final notifier =
        ref.read(itineraryDetailProvider(widget.itineraryId).notifier);

    // API path (edit mode or stop already exists):
    // Pass onSaveAsync so the annotation screen shows a spinner and pops itself
    // only after the API call completes — user sees feedback before returning.
    if (existing != null || widget.isEditMode) {
      await showAnnotationScreen(
        context,
        isEdit: existing != null,
        initialContent: existing?.content,
        initialType: existing?.type,
        stopName: _placeNameController.text.trim().isNotEmpty
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
      stopName: _placeNameController.text.trim().isNotEmpty
          ? _placeNameController.text.trim()
          : null,
    );
    if (result == null || !mounted) return;
    setState(() =>
        _pendingAnnotations.add(_PendingAnnotation(result.type, result.content)));
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool readOnly = widget.viewOnly && !_isEditing;
    // Edit mode shows every field at once so users can jump straight to what
    // they need to change. Only collapse for first-time creation.
    final bool collapseOptional =
        !widget.isEditMode && !readOnly && !_showOptional;
    final suggestionsAsync = ref.watch(placeSearchProvider);
    final duplicate = _findDuplicate();

    final currentUserId = ref.watch(myProfileProvider).value?.id;
    final itineraryAsync = ref.watch(itineraryDetailProvider(widget.itineraryId));
    final isOwner = currentUserId != null &&
        itineraryAsync.value?.userId == currentUserId;
    final bool showEditHint = readOnly && isOwner;

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

    final l10n = AppLocalizations.of(context)!;
    final appBarTitle = readOnly
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
      child: Scaffold(
      backgroundColor: kSand,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: kSand,
        title: Text(appBarTitle),
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
                  onTap: () => setState(() => _isEditing = true),
                ),
              ),
            ),
          if (!readOnly)
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: NTripiRingLoader(size: 20),
                  )
                : TextButton(
                    onPressed: _save,
                    child: Text(
                     l10n.save,
                      style: const TextStyle(
                        color: kForest,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ----------------------------------------------------------------
                  // Section 1: Place search (hidden in view mode)
                  // ----------------------------------------------------------------
                  if (!readOnly) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: LabelWithHelp(
                        label: l10n.searchForPlaceLabel,
                        helpTitle: l10n.searchAPlaceHelpTitle,
                        helpMessage: l10n.searchAPlaceHelpMessage,
                        labelStyle: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: l10n.searchPlaceHintText,
                        filled: true,
                        fillColor: kSurface,
                        prefixIcon:
                            const Icon(Icons.search_rounded, color: kForest),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(placeSearchProvider.notifier).clear();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: kBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: kBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: kForest, width: 1.5),
                        ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    ),

                    // Suggestions list
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: suggestionsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (suggestions) {
                        if (suggestions.isEmpty) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kBorder),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < suggestions.length; i++) ...[
                                if (i > 0)
                                  const Divider(height: 1, indent: 52),
                                ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: kSand,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.location_on_rounded,
                                        size: 18, color: kForest),
                                  ),
                                  title: Text(suggestions[i].displayName,
                                      maxLines: 1,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: kBark)),
                                  subtitle: Text(
                                    suggestions[i].address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11, color: kText2),
                                  ),
                                  trailing: const Icon(Icons.add_rounded,
                                      size: 20, color: kForest),
                                  onTap: () =>
                                      _applySuggestion(suggestions[i]),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Place name + address ───────────────────────────────
                  _SFSectionCard(
                    children: [
                      _SFBorderlessField(
                        label: l10n.placeNameLabel.toUpperCase(),
                        childBuilder: (focusNode) => TextFormField(
                          controller: _placeNameController,
                          focusNode: focusNode,
                          readOnly: readOnly,
                          onTap: showEditHint ? _showEditModeHint : null,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: '—',
                          ),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: kBark),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? l10n.placeNameRequired
                              : null,
                        ),
                      ),
                      const _SFDivider(),
                      _SFBorderlessField(
                        label: l10n.addressLabel.toUpperCase(),
                        childBuilder: (focusNode) => TextFormField(
                          controller: _placeAddressController,
                          focusNode: focusNode,
                          readOnly: readOnly,
                          onTap: showEditHint ? _showEditModeHint : null,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: '—',
                          ),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: kBark),
                        ),
                      ),
                    ],
                  ),

                  // ── Location picker ────────────────────────────────────
                  const SizedBox(height: 8),
                  _SFSectionCard(
                    children: [
                      _SFPickerRow(
                        icon: Icons.map_rounded,
                        label: l10n.locationLabel.toUpperCase(),
                        value: _lat != null && _lng != null
                            ? 'Lat: ${_lat!.toStringAsFixed(5)}, Lng: ${_lng!.toStringAsFixed(5)}'
                            : l10n.noLocationSet,
                        onTap: readOnly ? null : _pickOnMap,
                      ),
                    ],
                  ),

                  // ── Duplicate warning ──────────────────────────────────
                  if (!widget.isEditMode && duplicate != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: kTransitBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kTransitBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: kTransitIcon),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.alreadyInItinerary(
                                  duplicate.placeName ?? l10n.aStopFallback),
                              style: const TextStyle(
                                  fontSize: 12, color: kTransitText),
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
                          onTap: () =>
                              setState(() => _showOptional = !_showOptional),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showOptional
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: kForest,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showOptional
                                      ? l10n.hideOptionalFields
                                      : l10n.showOptionalFields,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: kForest,
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
                  _SFSectionLabel(text: l10n.detailsSection.toUpperCase()),
                  _SFSectionCard(
                    children: [
                      // Place type
                      _SFPickerRow(
                        icon: _placeType?.icon ?? Icons.category_rounded,
                        iconColor: _placeType?.color ?? kForest,
                        label: l10n.placeTypeLabel.toUpperCase(),
                        value: _placeType?.label(l10n) ?? '—',
                        onTap: readOnly ? null : _showPlaceTypePicker,
                      ),
                      const _SFDivider(),
                      // Duration
                      _SFPickerRow(
                        icon: Icons.schedule_rounded,
                        label: l10n.timeToSpendModalTitle.toUpperCase(),
                        value: _durationLabel,
                        onTap: readOnly ? null : _showDurationPicker,
                      ),
                      const _SFDivider(),
                      // Free toggle
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: kMist,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.payments_rounded,
                                  size: 16, color: kForest),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.costLabel.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: kText2,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  Text(
                                    l10n.stopIsFree,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: kBark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isFree,
                              onChanged: readOnly
                                  ? null
                                  : (v) => setState(() => _isFree = v),
                              thumbColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.disabled)) {
                                  // disabled-on: muted forest; disabled-off: grey
                                  return states.contains(WidgetState.selected)
                                      ? kForest.withAlpha(160)
                                      : const Color(0xFFABBAAF);
                                }
                                return states.contains(WidgetState.selected)
                                    ? kForest
                                    : Colors.white;
                              }),
                              trackColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.disabled)) {
                                  return states.contains(WidgetState.selected)
                                      ? kMist.withAlpha(200)
                                      : const Color(0xFFD4DAD6);
                                }
                                return states.contains(WidgetState.selected)
                                    ? kMist
                                    : const Color(0xFFD4DAD6);
                              }),
                            ),
                          ],
                        ),
                      ),
                      if (!_isFree) ...[
                        const _SFDivider(),
                        _SFBorderlessField(
                          label: l10n.costLabel.toUpperCase(),
                          childBuilder: (focusNode) => TextFormField(
                            controller: _costController,
                            focusNode: focusNode,
                            readOnly: readOnly,
                            onTap: showEditHint ? _showEditModeHint : null,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: l10n.stopCostHint,
                              prefixText: '€ ',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: kBark),
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
                  _SFSectionLabel(text: l10n.notesLabel.toUpperCase()),
                  _SFSectionCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: MarkdownNotesEditor(
                          controller: _notesController,
                          readOnly: readOnly,
                          label: l10n.thoughtsLabel,
                          helpTitle: l10n.thoughtsLabel,
                          helpMessage: l10n.thoughtsHelp,
                        ),
                      ),
                    ],
                  ),

                  // ── ANNOTATIONS ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(22, 14, 16, 6),
                    child: Row(
                      children: [
                        Text(
                          l10n.annotationsSection.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kText2,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const Spacer(),
                        if (!readOnly)
                          GestureDetector(
                            onTap: () => _showAnnotationDialog(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_rounded,
                                    size: 14, color: kForest),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.addButton,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kForest,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _buildAnnotationsContent(
                        context, readOnly, l10n),
                  ),
                  ],

                  // ── Delete (edit mode, non-readonly) ───────────────────
                  if (!readOnly && widget.isEditMode) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _confirmDelete,
                        icon: const Icon(Icons.delete_outline,
                            color: kRatingRed),
                        label: Text(
                          l10n.deleteStopButton,
                          style: const TextStyle(color: kRatingRed),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kRatingRed),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  // ── Place type picker bottom sheet ──────────────────────────────────────
  Future<void> _showPlaceTypePicker() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                    color: kText3.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  AppLocalizations.of(context)!.placeTypeLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: PlaceType.values.map((t) {
                    final l10n = AppLocalizations.of(context)!;
                    final selected = _placeType == t;
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: t.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(t.icon, size: 18, color: t.color),
                      ),
                      title: Text(t.label(l10n),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: kBark)),
                      subtitle: Text(t.hint(l10n),
                          style: const TextStyle(
                              fontSize: 11, color: kText2)),
                      trailing: selected
                          ? const Icon(Icons.check_rounded,
                              color: kForest, size: 18)
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
                      color: kBorder,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.clear_rounded,
                        size: 18, color: kText3),
                  ),
                  title: Text(AppLocalizations.of(context)!.noneOption,
                      style: const TextStyle(color: kText2)),
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
      BuildContext context, bool readOnly, AppLocalizations l10n) {
    if (widget.isEditMode) {
      final annos = _existingStop?.annotations ?? [];
      if (annos.isEmpty) {
        return Text(l10n.noAnnotationsYet,
            style: const TextStyle(color: kText3, fontSize: 13));
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: annos
            .map((a) => AnnotationChip(
                  annotation: a,
                  onEdit: readOnly
                      ? null
                      : () => _showAnnotationDialog(existing: a),
                  onDelete: readOnly
                      ? null
                      : () => _deleteAnnotation(a.id),
                ))
            .toList(),
      );
    } else {
      if (_pendingAnnotations.isEmpty) {
        return Text(l10n.noAnnotationsYet,
            style: const TextStyle(color: kText3, fontSize: 13));
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: _pendingAnnotations
            .map((p) => AnnotationChip(
                  annotation: Annotation(
                    id: 'pending-${p.content.hashCode}',
                    stopId: '',
                    type: p.type,
                    content: p.content,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                  onDelete: () =>
                      setState(() => _pendingAnnotations.remove(p)),
                ))
            .toList(),
      );
    }
  }
}

// ─── Stop-form editorial helpers ─────────────────────────────────────────────

class _SFSectionLabel extends StatelessWidget {
  final String text;
  const _SFSectionLabel({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kText2,
            letterSpacing: 0.6,
          ),
        ),
      );
}

class _SFSectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SFSectionCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _SFDivider extends StatelessWidget {
  const _SFDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: kBorder, margin: const EdgeInsetsDirectional.only(start: 16));
}

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
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kText2,
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
    final tint = iconColor ?? kForest;
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
                color: kMist,
                borderRadius: BorderRadius.circular(10),
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kBark,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: kText3),
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
