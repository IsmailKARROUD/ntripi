// presentation/itinerary_detail_screen.dart — Full itinerary view with map.
//
// Layout (CustomScrollView so pull-to-refresh works over the whole page):
//   AppBar       — title | add-stop + add-segment + reorder icons (edit mode) | share + more_vert
//   Summary chips — duration, cost, safety rating, stop count, visibility
//   Description  — optional free-text
//   Rating section — community avg + current user's 5-star picker
//   Map section  — OSM map with stop markers and polyline (ODbL requires attribution)
//   Stop list    — interleaved stops + segments (read & edit mode)
//                  switches to standalone ReorderableListView in reorder mode
//   Save bar     — full-width FilledButton that slides up from the bottom in edit mode
//
// Edit-mode state machine:
//   _editMode = false          → read-only view
//   _editMode = true           → interleaved list with inline edit/delete buttons,
//                                inline separators between stops, save bar visible
//   _editMode + _reorderMode   → standalone ReorderableListView (stops only)
//                                drag handles work because there's no outer
//                                CustomScrollView to steal the gesture
//
// Pending reorder:
//   Stop reordering is deferred — changes accumulate in _pendingOrder and are
//   only sent to the server when the user taps Save. All other mutations (stop
//   edit/delete, segment edit/delete) call the API immediately from sub-screens.
//
// Back-button guard (PopScope):
//   While in edit mode, the system back button is intercepted. If the user has
//   a pending reorder they're asked to Save / Discard / Stay. If there are no
//   pending changes they just exit edit mode silently (don't navigate away).
//
// OSM attribution is required by the ODbL license and is always visible.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/annotation_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/move_stop_to_track_sheet.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/parallel_stop_group.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/segment_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/track_reorder_view.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/shadow_divider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/visibility_badge.dart';

class ItineraryDetailScreen extends ConsumerStatefulWidget {
  final String itineraryId;

  const ItineraryDetailScreen({super.key, required this.itineraryId});

  @override
  ConsumerState<ItineraryDetailScreen> createState() =>
      _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends ConsumerState<ItineraryDetailScreen> {
  bool _editMode = false;
  // Active parallel-stop index per track (trackId → page index).
  final Map<String, int> _activeParallelByTrack = {};
  // GlobalKey per track widget so we can call Scrollable.ensureVisible after a
  // cross-track move to scroll the destination track into view.
  final Map<String, GlobalKey> _trackKeys = {};
  //start with map hidden on mobile to avoid unnecessary API calls and improve performance, since the map is less likely to be used on mobile and can be accessed via a button
  bool _mapVisible = false;
  final TextEditingController _descriptionController = TextEditingController();
  // Snapshot of the description as last saved; null outside of edit sessions.
  String? _savedDescription;
  bool _descriptionDirty = false;
  bool _descriptionSaving = false;

  static const _markerColors = {
    StopType.origin: kForest,
    StopType.waypoint: kCanopy,
    StopType.arrival: kRatingRed,
  };

  @override
  void initState() {
    super.initState();
    // Rebuild only when dirty state flips, not on every keystroke.
    _descriptionController.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_onDescriptionChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    final dirty =
        _descriptionController.text.trim() != (_savedDescription ?? '');
    if (dirty != _descriptionDirty) setState(() => _descriptionDirty = dirty);
  }

  void _enterEditMode() {
    final itinerary =
        ref.read(itineraryDetailProvider(widget.itineraryId)).valueOrNull;
    final desc = itinerary?.description ?? '';
    _savedDescription =
        desc; // must be set before controller.text to avoid a false dirty signal
    _descriptionController.text = desc;
    setState(() => _editMode = true);
  }

  Future<void> _undoDescription() async {
    // Undo wipes the in-progress edits back to the saved value — confirm first.
    final l10n = AppLocalizations.of(context)!;
    final discard = await confirmDestructiveAction(
      context: context,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discardButton,
      cancelLabel: l10n.keepEditingButton,
    );
    if (!discard || !mounted) return;
    _descriptionController.text = _savedDescription ?? '';
  }

  Future<void> _saveDescription() async {
    final newDesc = _descriptionController.text.trim();
    setState(() => _descriptionSaving = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateHeader({'description': newDesc.isEmpty ? null : newDesc});
      if (!mounted) return;
      setState(() {
        _savedDescription = newDesc;
        _descriptionDirty = false;
        _descriptionSaving = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _descriptionSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _exitEditMode() async {
    if (_descriptionDirty) {
      final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.unsavedDescriptionTitle),
          content:
              Text(AppLocalizations.of(context)!.unsavedDescriptionMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(context)!.discardButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      );
      if (save == null || !mounted) return; // dismissed → stay in edit mode
      if (save) {
        await _saveDescription();
        if (!mounted) return;
      }
    }
    if (mounted) {
      setState(() {
        _editMode = false;
        _descriptionDirty = false;
        _savedDescription = null;
      });
    }
  }

  /// Scrolls the outer CustomScrollView so that the track with the given ID
  /// becomes visible near the top. The post-frame callback waits for the
  /// detail-provider refresh to rebuild the list before resolving the key's
  /// context, otherwise the destination track may not yet be laid out.
  void _scrollToTrack(String trackId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _trackKeys[trackId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  Future<void> _addItineraryAnnotation() async {
    final result = await showAnnotationScreen(context);
    if (result == null || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .addItineraryAnnotation({
        'content': result.content,
        'type': result.type.name,
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _editItineraryAnnotation(ItineraryAnnotation annotation) async {
    final result = await showAnnotationScreen(
      context,
      isEdit: true,
      initialContent: annotation.content,
      initialType: annotation.type,
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateItineraryAnnotation(annotation.id,
              content: result.content, type: result.type);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _deleteItineraryAnnotation(
      ItineraryAnnotation annotation) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.deleteAnnotationTitle,
      message: l10n.deleteAnnotationMessage,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteItineraryAnnotation(annotation.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  // stop is passed so the screen can show the stop context card.
  Future<void> _addAnnotation(Stop stop) async {
    final result = await showAnnotationScreen(
      context,
      stopName: stop.placeName ?? 'Stop',
      stopSubtitle: stop.placeAddress,
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .addAnnotation(stop.id, {
        'content': result.content,
        'type': result.type.name,
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _editAnnotation(Stop stop, Annotation annotation) async {
    final result = await showAnnotationScreen(
      context,
      isEdit: true,
      initialContent: annotation.content,
      initialType: annotation.type,
      stopName: stop.placeName ?? 'Stop',
      stopSubtitle: stop.placeAddress,
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateAnnotation(stop.id, annotation.id,
              content: result.content, type: result.type);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _deleteAnnotation(String stopId, Annotation annotation) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.deleteAnnotationTitle,
      message: l10n.deleteAnnotationMessage,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteAnnotation(stopId, annotation.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _confirmDeleteSegment(TransitSegment segment) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.removeTransitTitle,
      message: l10n.removeTransitMessage,
      confirmLabel: l10n.removeButton,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteSegment(segment.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _addSegmentWithLeg(String fromStopId, String toStopId) async {
    final legData = await LegFormDialog.show(context);
    if (!mounted || legData == null) return;
    final data = <String, dynamic>{
      'from_stop_id': fromStopId,
      'to_stop_id': toStopId,
      'legs': [
        {...legData, 'position': 1},
      ],
    };
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .createSegment(data);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(widget.itineraryId));
    final currentUserId = ref.watch(myProfileProvider).valueOrNull?.id;
    final isOwner = currentUserId != null &&
        itineraryAsync.valueOrNull?.userId == currentUserId;

    final ownerUserId = itineraryAsync.valueOrNull?.userId ?? '';

    return PopScope(
      canPop: !_editMode,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _exitEditMode();
      },
      child: Scaffold(
        backgroundColor: kSurface,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: false, // cover hero extends behind status bar
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth:
                      isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
              child: itineraryAsync.when(
                loading: () => const Center(child: NTripiRouteLoader()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        extractErrorMessage(
                            error as dynamic, AppLocalizations.of(context)!),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref
                            .read(itineraryDetailProvider(widget.itineraryId)
                                .notifier)
                            .refresh(),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
                data: (itinerary) {
                  final allStops = itinerary.stops;
                  final tracks = itinerary.tracks;
                  final canEdit = isOwner && _editMode;

                  final segmentByFromStop = {
                    for (final seg in itinerary.segments) seg.fromStopId: seg,
                  };
                  // Keyed by toStopId so read mode can look up the inbound
                  // segment and show it before the destination stop.
                  final segmentByToStop = {
                    for (final seg in itinerary.segments) seg.toStopId: seg,
                  };
                  final mappableStops = allStops
                      .where((s) => s.lat != null && s.lng != null)
                      .toList();
                  final polylinePoints =
                      mappableStops.map((s) => LatLng(s.lat!, s.lng!)).toList();
                  final mapCenter = mappableStops.isNotEmpty
                      ? LatLng(
                          mappableStops.first.lat!, mappableStops.first.lng!)
                      : const LatLng(48.8566, 2.3522);

                  // Build interleaved list from tracks (server already sorted by rank).
                  List<Widget> buildInterleavedList() {
                    final items = <Widget>[];
                    for (var i = 0; i < tracks.length; i++) {
                      final track = tracks[i];
                      final trackStops = track.stops;
                      if (trackStops.isEmpty) continue;
                      final hasNextTrack = i < tracks.length - 1;
                      final nextTrack = hasNextTrack ? tracks[i + 1] : null;
                      final trackIndex = i + 1;

                      // Divider between stop groups (not before the first).
                      if (items.isNotEmpty) {
                        items.add(const ShadowDivider(
                            height: 1, indent: 14, endIndent: 14));
                      }

                      // READ MODE: show the inbound transit BEFORE this stop
                      // (i.e. the segment that arrives at the active parallel).
                      // Edit mode keeps the transit below the origin stop (handled
                      // by getSegment inside ParallelStopGroup below).
                      if (!canEdit && i > 0) {
                        final activeIdx = _activeParallelByTrack[track.id] ?? 0;
                        final activeStop = trackStops.length > activeIdx
                            ? trackStops[activeIdx]
                            : trackStops.first;
                        final inbound = segmentByToStop[activeStop.id];
                        if (inbound != null) {
                          items.add(SegmentCard(
                            key: ValueKey('seg-in-${inbound.id}'),
                            segment: inbound,
                            currency: itinerary.currency,
                            itineraryId: widget.itineraryId,
                            // no onEdit/onDelete → renders as compact _TransitRow
                          ));
                        }
                      }

                      items.add(ParallelStopGroup(
                        key:
                            _trackKeys.putIfAbsent(track.id, () => GlobalKey()),
                        stops: trackStops,
                        currency: itinerary.currency,
                        itineraryId: widget.itineraryId,
                        editMode: canEdit,
                        trackIndex: trackIndex,
                        canMoveToTrack: canEdit,
                        onMoveToTrack: canEdit
                            ? (activeStop) => showMoveStopToTrackSheet(
                                  context: context,
                                  itineraryId: widget.itineraryId,
                                  stop: activeStop,
                                  tracks: tracks,
                                  segments: itinerary.segments,
                                  onMoved: _scrollToTrack,
                                )
                            : null,
                        getSegment: (fromStopId) {
                          // Read mode: transit is rendered before the destination
                          // stop in buildInterleavedList, not inside the group.
                          if (!canEdit) return null;
                          final seg = segmentByFromStop[fromStopId];
                          if (seg == null) return null;
                          if (nextTrack != null) {
                            final nextIdx =
                                _activeParallelByTrack[nextTrack.id] ?? 0;
                            final nextStop = nextTrack.stops.length > nextIdx
                                ? nextTrack.stops[nextIdx]
                                : nextTrack.stops.first;
                            if (seg.toStopId != nextStop.id) return null;
                          }
                          return seg;
                        },
                        onViewStop: (stop) => context.push(
                          '/itineraries/${widget.itineraryId}/stops/${stop.id}',
                        ),
                        onAddParallel: canEdit
                            ? (trackId) => context.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {'trackId': trackId},
                                )
                            : null,
                        onEditStop: canEdit
                            ? (stop) => context.push(
                                  '/itineraries/${widget.itineraryId}/stops/${stop.id}/edit',
                                )
                            : null,
                        onAddAnnotation:
                            canEdit ? (stop) => _addAnnotation(stop) : null,
                        onEditAnnotation: canEdit
                            ? (stop, a) => _editAnnotation(stop, a)
                            : null,
                        onDeleteAnnotation: canEdit
                            ? (stop, a) => _deleteAnnotation(stop.id, a)
                            : null,
                        onEditSegment: canEdit
                            ? (seg) => context.push(
                                  '/itineraries/${widget.itineraryId}/segments/${seg.id}/edit',
                                )
                            : null,
                        onDeleteSegment: canEdit ? _confirmDeleteSegment : null,
                        onAddTransit: canEdit && nextTrack != null
                            ? (fromStopId) {
                                final nextIdx =
                                    _activeParallelByTrack[nextTrack.id] ?? 0;
                                final toStop = nextTrack.stops.length > nextIdx
                                    ? nextTrack.stops[nextIdx]
                                    : nextTrack.stops.first;
                                return _addSegmentWithLeg(
                                    fromStopId, toStop.id);
                              }
                            : null,
                        onPageChanged: (idx) => setState(() {
                          _activeParallelByTrack[track.id] = idx;
                        }),
                        onAddStopBefore: canEdit && i == 0
                            ? () async {
                                context.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {'beforeTrackId': track.id},
                                );
                              }
                            : null,
                        onAddStopAfter: canEdit
                            ? () async {
                                final router = GoRouter.of(context);
                                // SEGMENT ORPHAN CHECK: inserting a new track
                                // between track[i] and track[i+1] hides any
                                // segment connecting their stops (it still
                                // exists but is no longer between adjacent
                                // tracks). Warn the user and offer deletion.
                                if (nextTrack != null) {
                                  final nextStopIds =
                                      nextTrack.stops.map((s) => s.id).toSet();
                                  final orphaned = trackStops
                                      .map((s) => segmentByFromStop[s.id])
                                      .whereType<TransitSegment>()
                                      .where((seg) =>
                                          nextStopIds.contains(seg.toStopId))
                                      .toList();

                                  if (orphaned.isNotEmpty) {
                                    final n = orphaned.length;
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(
                                            l10n.deleteOrphanSegmentsTitle(n)),
                                        content: Text(l10n
                                            .deleteOrphanSegmentsMessage(n)),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: Text(l10n.cancel),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: kRatingRed,
                                            ),
                                            child: Text(l10n.deleteAndContinue),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmed != true || !mounted) return;

                                    final notifier = ref.read(
                                      itineraryDetailProvider(
                                              widget.itineraryId)
                                          .notifier,
                                    );
                                    for (final seg in orphaned) {
                                      await notifier.deleteSegment(seg.id);
                                    }
                                    if (!mounted) return;
                                  }
                                }

                                router.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {
                                    'afterTrackId': track.id,
                                    if (nextTrack != null)
                                      'beforeTrackId': nextTrack.id,
                                  },
                                );
                              }
                            : null,
                      ));
                    }
                    return items;
                  }

                  // Resolve absolute cover URL once.
                  final coverUrl = itinerary.coverImageUrl != null
                      ? (itinerary.coverImageUrl!.startsWith('/')
                          ? '$kApiBaseUrl${itinerary.coverImageUrl}'
                          : itinerary.coverImageUrl!)
                      : null;

                  return RefreshIndicator(
                    onRefresh: () async {
                      // R2 reuses the same key on cover replacement, so the
                      // URL string never changes. Evict CachedNetworkImage's
                      // disk + memory entry for the current cover URL so a
                      // pull-to-refresh actually shows the new image when
                      // the owner has replaced it from another device.
                      if (coverUrl != null) {
                        await CachedNetworkImage.evictFromCache(
                          coverUrl,
                          cacheManager: NtripiImageCacheManager(),
                        );
                      }
                      await ref
                          .read(itineraryDetailProvider(widget.itineraryId)
                              .notifier)
                          .refresh();
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // ── Cover hero (240px full-bleed) ──────────────────
                        SliverToBoxAdapter(
                          child: _CoverHero(
                            coverUrl: coverUrl,
                            itinerary: itinerary,
                            isOwner: isOwner,
                            editMode: _editMode,
                            onBack: () => context.pop(),
                            onShare: itinerary.visibility !=
                                    ItineraryVisibility.onlyMe
                                ? () => ref
                                    .read(shareServiceProvider)
                                    .shareItinerary(itinerary)
                                : null,
                            onEditDetails: isOwner
                                ? () => context.push(
                                    '/itineraries/${widget.itineraryId}/edit')
                                : null,
                            onEnterEdit:
                                isOwner && !_editMode ? _enterEditMode : null,
                            onExitEdit:
                                isOwner && _editMode ? _exitEditMode : null,
                          ),
                        ),

                        // ── Owner row ──────────────────────────────────────
                        if (ownerUserId.isNotEmpty)
                          SliverToBoxAdapter(
                            child: ref
                                .watch(userProfileProvider(ownerUserId))
                                .when(
                                  loading: () => const OwnerRowSkeleton(),
                                  error: (_, __) => const SizedBox.shrink(),
                                  data: (owner) => _OwnerRow(
                                    owner: owner,
                                    itinerary: itinerary,
                                    itineraryId: widget.itineraryId,
                                  ),
                                ),
                          ),

                        // ── Meta chips ─────────────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _DetailMetaChip(
                                  icon: Icons.schedule_rounded,
                                  label: itinerary.formattedDuration,
                                ),
                                _DetailMetaChip(
                                  icon: Icons.payments_rounded,
                                  label: itinerary.formattedCost,
                                ),
                                _DetailMetaChip(
                                  icon: Icons.location_on_rounded,
                                  label: l10n.stopCount(allStops.length),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Description ────────────────────────────────────
                        if (canEdit)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  MarkdownNotesEditor(
                                    controller: _descriptionController,
                                    readOnly: false,
                                    label: l10n.descriptionLabel,
                                    helpTitle: l10n.descriptionLabel,
                                    helpMessage: l10n.descriptionHelp,
                                  ),
                                  if (_descriptionDirty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: _descriptionSaving
                                          ? const Align(
                                              alignment:
                                                  AlignmentGeometry.center,
                                              child: NTripiDotsLoader(dotSize: 10,))
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 16),
                                                  child: TextButton.icon(
                                                    onPressed: _undoDescription,
                                                    icon: const Icon(
                                                        Icons.undo_rounded,
                                                        color: kRatingRed,
                                                        size: 16),
                                                    label: const Text(
                                                      'Undo',
                                                      style: TextStyle(
                                                          color: kRatingRed),
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 16),
                                                  child: FilledButton(
                                                    onPressed:
                                                        _descriptionSaving
                                                            ? null
                                                            : _saveDescription,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              left: 16,
                                                              right: 16),
                                                      child: Text(AppLocalizations
                                                              .of(context)!
                                                          .saveDescriptionLabel),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        else if (itinerary.description != null &&
                            itinerary.description!.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: InertMarkdownBody(
                                  data: itinerary.description!),
                            ),
                          ),

                        // ── Itinerary annotations ──────────────────────────
                        if (itinerary.annotations.isNotEmpty || canEdit)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        l10n.annotationsSection,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: kText2,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      if (canEdit) ...[
                                        const Spacer(),
                                        // Tinted pill matching the stop-card "Add note" affordance.
                                        GestureDetector(
                                          onTap: _addItineraryAnnotation,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: kEditBlueTint,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color: kEditBlue.withValues(
                                                      alpha: 0.13)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.add_rounded,
                                                    size: 13, color: kEditBlue),
                                                const SizedBox(width: 3),
                                                Text(
                                                  l10n.addAnnotationButton,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: kEditBlue),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (itinerary.annotations.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, bottom: 4),
                                      child: Text(
                                        l10n.noAnnotationsYet,
                                        style: const TextStyle(
                                            color: kText3, fontSize: 13),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: itinerary.annotations
                                            .map(
                                              (a) => AnnotationChip(
                                                annotation: Annotation(
                                                  id: a.id,
                                                  stopId: a.itineraryId,
                                                  type: a.type,
                                                  content: a.content,
                                                  createdAt: a.createdAt,
                                                  updatedAt: a.updatedAt,
                                                ),
                                                onEdit: canEdit
                                                    ? () =>
                                                        _editItineraryAnnotation(
                                                            a)
                                                    : null,
                                                onDelete: canEdit
                                                    ? () =>
                                                        _deleteItineraryAnnotation(
                                                            a)
                                                    : null,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                        // ── List / Map toggle ──────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                            child: Row(
                              children: [
                                Text(
                                  _mapVisible
                                      ? l10n.mapSection
                                      : canEdit
                                          ? l10n.editStopsButton
                                          : l10n.stopsList,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: kText2,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const Spacer(),
                                // Edit mode controls
                                if (canEdit &&
                                    itineraryAsync.valueOrNull != null &&
                                    itineraryAsync.valueOrNull!.tracks.length >=
                                        2) ...[
                                  EditPencilButton(
                                    icon: Icons.reorder,
                                    iconSize: 20,
                                    tooltip: l10n.reorderTracksTooltip,
                                    onTap: () => showTrackReorderSheet(
                                      context: context,
                                      itineraryId: widget.itineraryId,
                                      tracks:
                                          itineraryAsync.valueOrNull!.tracks,
                                      segments:
                                          itineraryAsync.valueOrNull!.segments,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // List/Map pill toggle
                                _SegmentToggle(
                                  showMap: _mapVisible,
                                  onChanged: (showMap) =>
                                      setState(() => _mapVisible = showMap),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Map ────────────────────────────────────────────
                        if (_mapVisible)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  height: 200,
                                  child: Stack(
                                    children: [
                                      FlutterMap(
                                        options: MapOptions(
                                          initialCenter: mapCenter,
                                          initialZoom:
                                              mappableStops.isNotEmpty ? 12 : 5,
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate:
                                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                            userAgentPackageName:
                                                'com.ntripi.app',
                                          ),
                                          if (polylinePoints.length >= 2)
                                            PolylineLayer(
                                              polylines: [
                                                Polyline(
                                                  points: polylinePoints,
                                                  color: kCanopy.withValues(
                                                      alpha: 0.6),
                                                  strokeWidth: 3,
                                                ),
                                              ],
                                            ),
                                          MarkerLayer(
                                            markers: mappableStops.map((stop) {
                                              final color =
                                                  _markerColors[stop.type] ??
                                                      kText2;
                                              return Marker(
                                                point: LatLng(
                                                    stop.lat!, stop.lng!),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(3),
                                                  decoration: BoxDecoration(
                                                    color: color,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: Colors.white,
                                                        width: 2),
                                                  ),
                                                  child: const Icon(Icons.place,
                                                      color: Colors.white,
                                                      size: 10),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                          RichAttributionWidget(
                                            attributions: [
                                              TextSourceAttribution(l10n
                                                  .openStreetMapContributors),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // ── Stop list or empty state ────────────────────────
                        if (tracks.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                              child: canEdit
                                  ? GestureDetector(
                                      onTap: () => context.push(
                                        '/itineraries/${widget.itineraryId}/stops/new',
                                      ),
                                      child: Column(
                                        children: [
                                          const Icon(Icons.place_outlined,
                                              size: 48, color: kText3),
                                          const SizedBox(height: 12),
                                          Text(l10n.noStopsYetTapPlus),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        const Icon(Icons.place_outlined,
                                            size: 48, color: kText3),
                                        const SizedBox(height: 12),
                                        Text(l10n.noStopsYet),
                                      ],
                                    ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              decoration: BoxDecoration(
                                color: kSurface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: kBorder),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: buildInterleavedList(),
                              ),
                            ),
                          ),

                        // ── Rate this trip CTA (read mode) ─────────────────
                        if (!canEdit && tracks.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: _RateCta(
                                itineraryId: widget.itineraryId,
                                itinerary: itinerary,
                              ),
                            ),
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Cover hero (240 px full-bleed) ──────────────────────────────────────────
// Back button top-left; share / edit / done top-right (glassmorphism).
// Visibility badge + title + location overlay at the bottom.
class _CoverHero extends StatefulWidget {
  final String? coverUrl;
  final Itinerary itinerary;
  final bool isOwner;
  final bool editMode;
  final VoidCallback onBack;
  final VoidCallback? onShare;
  final VoidCallback? onEditDetails;
  final VoidCallback? onEnterEdit;
  final VoidCallback? onExitEdit;

  const _CoverHero({
    required this.coverUrl,
    required this.itinerary,
    required this.isOwner,
    required this.editMode,
    required this.onBack,
    this.onShare,
    this.onEditDetails,
    this.onEnterEdit,
    this.onExitEdit,
  });

  @override
  State<_CoverHero> createState() => _CoverHeroState();
}

class _CoverHeroState extends State<_CoverHero> {
  bool _imgError = false;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final itinerary = widget.itinerary;

    return SizedBox(
      height: 240 + topPad,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover image or gradient placeholder
          if (widget.coverUrl != null && !_imgError)
            CachedNetworkImage(
              imageUrl: widget.coverUrl!,
              cacheManager: NtripiImageCacheManager(),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _imgError = true);
                });
                return const _HeroPlaceholder();
              },
            )
          else
            const _HeroPlaceholder(),

          // Gradient overlay: dark at top + bottom, transparent in middle
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 0.6, 1.0],
                colors: [
                  Color(0x661A2A1E),
                  Color(0x001A2A1E),
                  Color(0x001A2A1E),
                  Color(0xB31A2A1E),
                ],
              ),
            ),
          ),

          // Top chrome: back button left, actions right
          Positioned(
            top: topPad + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [ 
                if (widget.editMode) ...[
                  const Spacer(),
                  _GlassButton(
                    icon: Icons.check_rounded,
                    onTap: widget.onExitEdit,
                  ),
                ] else ...[
                                  _GlassButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: widget.onBack,
                ),
                  const Spacer(),
                  if (widget.onShare != null) ...[
                    _GlassButton(
                      icon: Icons.share_rounded,
                      onTap: widget.onShare,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (widget.isOwner) ...[
                    _GlassButton(
                      icon: Icons.tune_rounded,
                      onTap: widget.onEditDetails,
                    ),
                    const SizedBox(width: 6),
                    EditPencilButton(
                      onTap: widget.onEnterEdit,
                      iconSize: 22,
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Bottom overlay: visibility badge + title + location
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                VisibilityBadge(visibility: itinerary.visibility, onDark: true),
                const SizedBox(height: 8),
                Text(
                  itinerary.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kForest, kCanopy],
        ),
      ),
    );
  }
}

// Small frosted-glass icon button for the hero overlay.
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _GlassButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          // dark tint ensures visibility against any cover image, incl. white
          color: kButtonTransparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// Visibility badge styled for the dark hero overlay.
// ─── Owner row ────────────────────────────────────────────────────────────────
// Owner avatar + name + personal rating (viewer) + community rating.
// Community rating (right) taps → ratings screen.
// Personal rating (middle) taps → rate dialog.
class _OwnerRow extends ConsumerWidget {
  final User owner;
  final Itinerary itinerary;
  final String itineraryId;

  const _OwnerRow({
    required this.owner,
    required this.itinerary,
    required this.itineraryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarUrl = owner.avatarUrl != null
        ? (owner.avatarUrl!.startsWith('/')
            ? '$kApiBaseUrl${owner.avatarUrl}'
            : owner.avatarUrl!)
        : null;
    final ratingAvg = itinerary.ratingAvg;
    final myRating = ref.watch(myRatingProvider(itineraryId)).valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          // Owner avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: kMist,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(
                    avatarUrl,
                    cacheManager: NtripiImageCacheManager(),
                  )
                : null,
            child: avatarUrl == null
                ? Text(
                    owner.nameForDisplay.isNotEmpty
                        ? owner.nameForDisplay[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: kForest, fontWeight: FontWeight.w700),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  owner.nameForDisplay,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kBark,
                  ),
                ),
                Text(
                  owner.handle,
                  style: const TextStyle(fontSize: 11, color: kText2),
                ),
              ],
            ),
          ),

          // ── Viewer's personal rating ────────────────────────────────────
          GestureDetector(
            onTap: () => showRateItineraryDialog(
              context,
              ref,
              itineraryId: itineraryId,
              current: myRating,
            ),
            child: myRating != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(
                          5,
                          (i) => Icon(
                                i < myRating.stars
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 14,
                                color: i < myRating.stars
                                    ? ratingColor(myRating.stars.toDouble())
                                    : kText3,
                              )),
                      const SizedBox(width: 4),
                      const Icon(Icons.person_rounded,
                          size: 11, color: kForest),
                    ],
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: kForest),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 13, color: kForest),
                        SizedBox(width: 4),
                        Text(
                          'Rate',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kForest),
                        ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(width: 10),
          Container(width: 1.1, height: 8, color: kBark),
          const SizedBox(width: 10),
          // ── Community rating ────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push('/itineraries/$itineraryId/ratings'),
            child: ratingAvg != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_rounded,
                          size: 11, color: kForest),
                      const SizedBox(width: 4),
                      Icon(Icons.star_rounded,
                          size: 13, color: ratingColor(ratingAvg)),
                      const SizedBox(width: 4),
                      Text(
                        ratingAvg.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ratingColor(ratingAvg),
                        ),
                      ),
                      Text(
                        ' (${itinerary.ratingCount})',
                        style: const TextStyle(
                            fontSize: 11,
                            color: kText3,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_outline_rounded, size: 14, color: kText3),
                      SizedBox(width: 4),
                      Text('—', style: TextStyle(fontSize: 12, color: kText3)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail meta chip ─────────────────────────────────────────────────────────
class _DetailMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x0A000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kBark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: kBark,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── List / Map pill toggle ───────────────────────────────────────────────────
class _SegmentToggle extends StatelessWidget {
  final bool showMap;
  final void Function(bool showMap) onChanged;

  const _SegmentToggle({required this.showMap, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kMist,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(
              icon: Icons.list_rounded,
              active: !showMap,
              onTap: () => onChanged(false)),
          _Tab(
              icon: Icons.map_rounded,
              active: showMap,
              onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _Tab({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 28,
        decoration: BoxDecoration(
          color: active ? kSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: active ? kForest : kText2,
        ),
      ),
    );
  }
}

// ─── Rate this trip CTA ───────────────────────────────────────────────────────
class _RateCta extends ConsumerWidget {
  final String itineraryId;
  final Itinerary itinerary;

  const _RateCta({required this.itineraryId, required this.itinerary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRating = ref.watch(myRatingProvider(itineraryId)).valueOrNull;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: () => showRateItineraryDialog(
          context,
          ref,
          itineraryId: itineraryId,
          current: myRating,
        ),
        icon: const Icon(Icons.star_rounded, size: 18),
        label: Text(myRating != null ? 'Update your rating' : 'Rate this trip'),
        style: FilledButton.styleFrom(
          backgroundColor: kForest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
