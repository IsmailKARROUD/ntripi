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
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_form_dialog.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/move_stop_to_track_sheet.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/parallel_stop_group.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/track_reorder_view.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:photo_view/photo_view.dart';

class ItineraryDetailScreen extends ConsumerStatefulWidget {
  final String itineraryId;

  const ItineraryDetailScreen({super.key, required this.itineraryId});

  @override
  ConsumerState<ItineraryDetailScreen> createState() =>
      _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends ConsumerState<ItineraryDetailScreen> {
  bool _editMode = false;
  // Phase 2b: when true, the body renders TrackReorderView instead of the
  // normal CustomScrollView. The view manages its own dirty/Save/Cancel state
  // and calls back via onExit to flip this off.
  bool _reorderMode = false;
  // Active parallel-stop index per track (trackId → page index).
  final Map<String, int> _activeParallelByTrack = {};
  // GlobalKey per track widget so we can call Scrollable.ensureVisible after a
  // cross-track move to scroll the destination track into view.
  final Map<String, GlobalKey> _trackKeys = {};
  //start with map hidden on mobile to avoid unnecessary API calls and improve performance, since the map is less likely to be used on mobile and can be accessed via a button
  bool _mapVisible = false;

  static const _markerColors = {
    StopType.origin: Colors.green,
    StopType.waypoint: Colors.blue,
    StopType.arrival: Colors.red,
  };

  void _enterEditMode() {
    setState(() => _editMode = true);
  }

  void _exitEditMode() {
    setState(() => _editMode = false);
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
    final result = await showAnnotationFormDialog(context, isEdit: false);
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _editItineraryAnnotation(ItineraryAnnotation annotation) async {
    final result = await showAnnotationFormDialog(
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _deleteItineraryAnnotation(
      ItineraryAnnotation annotation) async {
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: 'Delete annotation?',
      message: 'This will permanently remove this annotation from the itinerary.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteItineraryAnnotation(annotation.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _addAnnotation(String stopId) async {
    final result = await showAnnotationFormDialog(context, isEdit: false);
    if (result == null || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .addAnnotation(stopId, {
        'content': result.content,
        'type': result.type.name,
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _editAnnotation(String stopId, Annotation annotation) async {
    final result = await showAnnotationFormDialog(
      context,
      isEdit: true,
      initialContent: annotation.content,
      initialType: annotation.type,
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateAnnotation(stopId, annotation.id,
              content: result.content, type: result.type);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _deleteAnnotation(String stopId, Annotation annotation) async {
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: 'Delete annotation?',
      message: 'This will permanently remove this annotation from the itinerary.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteAnnotation(stopId, annotation.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  Future<void> _confirmDeleteSegment(TransitSegment segment) async {
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: 'Remove transit between stops?',
      message: 'The connection between these two stops will be cleared. '
          'You can add a new one later.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .deleteSegment(segment.id);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(widget.itineraryId));
    final currentUserId = ref.watch(myProfileProvider).valueOrNull?.id;
    final isOwner = currentUserId != null &&
        itineraryAsync.valueOrNull?.userId == currentUserId;

    return PopScope(
      canPop: !_editMode,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        setState(() => _editMode = false);
      },
      child: Stack(
        children: [
          Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              title: _reorderMode
                  ? const Text('Reorder tracks')
                  : itineraryAsync.when(
                      data: (i) => Text(i.title),
                      loading: () => const Text('Loading...'),
                      error: (_, __) => const Text('Itinerary'),
                    ),
              actions: [
                if (_reorderMode) ...[
                  // Reorder mode hides all other actions. The TrackReorderView
                  // has its own bottom Cancel + Save buttons, and the AppBar
                  // back arrow routes through the view's PopScope (which runs
                  // the discard-confirm when dirty).
                ] else if (isOwner && _editMode) ...[
                  IconButton(
                    icon: const Icon(Icons.add_location_alt_outlined),
                    tooltip: 'Add stop',
                    onPressed: () => context.push(
                      '/itineraries/${widget.itineraryId}/stops/new',
                    ),
                  ),
                  if (itineraryAsync.valueOrNull != null &&
                      itineraryAsync.valueOrNull!.tracks.length >= 2)
                    IconButton(
                      icon: const Icon(Icons.reorder),
                      tooltip: 'Reorder tracks',
                      onPressed: () => setState(() => _reorderMode = true),
                    ),
                  IconButton(
                    icon: const Icon(Icons.check),
                    tooltip: 'Done',
                    onPressed: _exitEditMode,
                  ),
                ] else ...[
                  if (itineraryAsync.valueOrNull != null &&
                      itineraryAsync.valueOrNull!.visibility !=
                          ItineraryVisibility.onlyMe)
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Share',
                      onPressed: () => ref
                          .read(shareServiceProvider)
                          .shareItinerary(itineraryAsync.value!),
                    ),
                  if (isOwner)
                    PopupMenuButton<_OwnerAction>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'More options',
                      onSelected: (action) async {
                        switch (action) {
                          case _OwnerAction.editStops:
                            _enterEditMode();
                          case _OwnerAction.editDetails:
                            context.push(
                                '/itineraries/${widget.itineraryId}/edit');
                          case _OwnerAction.delete:
                            final title = itineraryAsync.valueOrNull?.title ??
                                'this itinerary';
                            final router = GoRouter.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            final confirmed =
                                await confirmTypedDestructiveAction(
                              context: context,
                              title: 'Delete itinerary',
                              message:
                                  'This will permanently delete "$title" and all its stops. Type the title to confirm.',
                              requiredText: title,
                              hintText: title,
                            );
                            if (!confirmed || !mounted) return;
                            try {
                              await ref
                                  .read(myItinerariesProvider.notifier)
                                  .removeItinerary(widget.itineraryId);
                              if (!mounted) return;
                              router.go('/itineraries');
                            } on Exception catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                    content: Text(
                                        extractErrorMessage(e as dynamic))),
                              );
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: _OwnerAction.editStops,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit stops'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: _OwnerAction.editDetails,
                          child: ListTile(
                            leading: Icon(Icons.tune_outlined),
                            title: Text('Edit details & image'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: _OwnerAction.delete,
                          child: ListTile(
                            leading:
                                Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('Delete itinerary',
                                style: TextStyle(color: Colors.red)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth:
                        isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
                child: itineraryAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          extractErrorMessage(error as dynamic),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => ref
                              .read(itineraryDetailProvider(widget.itineraryId)
                                  .notifier)
                              .refresh(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  data: (itinerary) {
                    if (_reorderMode) {
                      return TrackReorderView(
                        itineraryId: widget.itineraryId,
                        tracks: itinerary.tracks,
                        segments: itinerary.segments,
                        onExit: () =>
                            setState(() => _reorderMode = false),
                      );
                    }
                    final allStops = itinerary.stops;
                    final tracks = itinerary.tracks;
                    final canEdit = isOwner && _editMode;

                    final segmentByFromStop = {
                      for (final seg in itinerary.segments) seg.fromStopId: seg,
                    };
                    final mappableStops = allStops
                        .where((s) => s.lat != null && s.lng != null)
                        .toList();
                    final polylinePoints = mappableStops
                        .map((s) => LatLng(s.lat!, s.lng!))
                        .toList();
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

                        items.add(ParallelStopGroup(
                          key: _trackKeys.putIfAbsent(
                              track.id, () => GlobalKey()),
                          stops: trackStops,
                          currency: itinerary.currency,
                          itineraryId: widget.itineraryId,
                          editMode: canEdit,
                          trackIndex: trackIndex,
                          // Phase 2c: visible whenever editing — the sheet
                          // always has *some* valid action (an existing track
                          // with capacity, a gap to create a new track, or an
                          // extract row when the source has parallels).
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
                          onAddAnnotation: canEdit
                              ? (stop) => _addAnnotation(stop.id)
                              : null,
                          onEditAnnotation: canEdit
                              ? (stop, a) => _editAnnotation(stop.id, a)
                              : null,
                          onDeleteAnnotation: canEdit
                              ? (stop, a) => _deleteAnnotation(stop.id, a)
                              : null,
                          onEditSegment: canEdit
                              ? (seg) => context.push(
                                    '/itineraries/${widget.itineraryId}/segments/${seg.id}/edit',
                                  )
                              : null,
                          onDeleteSegment:
                              canEdit ? _confirmDeleteSegment : null,
                          onAddTransit: canEdit && nextTrack != null
                              ? (fromStopId) {
                                  final nextIdx =
                                      _activeParallelByTrack[nextTrack.id] ?? 0;
                                  final toStop =
                                      nextTrack.stops.length > nextIdx
                                          ? nextTrack.stops[nextIdx]
                                          : nextTrack.stops.first;
                                  return _addSegmentWithLeg(
                                      fromStopId, toStop.id);
                                }
                              : null,
                          onPageChanged: (idx) => setState(() {
                            _activeParallelByTrack[track.id] = idx;
                          }),
                          onAddStopAfter: canEdit
                              ? () async {
                                  // Capture router before any await — accessing
                                  // BuildContext across async gaps is a lint error.
                                  final router = GoRouter.of(context);

                                  // SEGMENT ORPHAN CHECK:
                                  // A transit segment is displayed between two
                                  // ADJACENT tracks. If we insert a new track
                                  // between track[i] and track[i+1], any segment
                                  // that currently connects a stop in track[i] to
                                  // a stop in track[i+1] becomes invisible — it
                                  // still exists in the DB but is no longer between
                                  // adjacent tracks so the UI won't render it.
                                  // We detect this situation and warn the user,
                                  // offering to delete the orphaned segment(s)
                                  // before proceeding.
                                  if (nextTrack != null) {
                                    // Build a set of stop IDs in the next track
                                    // for fast membership tests below.
                                    final nextStopIds = nextTrack.stops
                                        .map((s) => s.id)
                                        .toSet();
                                    // Find segments whose fromStop is in the
                                    // current track AND whose toStop is in the
                                    // next track — these would become orphaned.
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
                                            'Delete transit segment${n > 1 ? 's' : ''}?',
                                          ),
                                          content: Text(
                                            'There ${n == 1 ? 'is 1 transit segment' : 'are $n transit segments'} '
                                            'connecting these two stops. '
                                            'Adding a stop between them will hide ${n == 1 ? 'it' : 'them'} '
                                            'because the stops will no longer be adjacent.\n\n'
                                            'Delete the segment${n > 1 ? 's' : ''} and continue?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Colors.red,
                                              ),
                                              child: const Text(
                                                  'Delete & continue'),
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

                    return RefreshIndicator(
                      onRefresh: () async {
                        // R2 reuses the same key on cover replacement, so the
                        // URL string never changes. Evict CachedNetworkImage's
                        // disk + memory entry for the current cover URL so a
                        // pull-to-refresh actually shows the new image when
                        // the owner has replaced it from another device.
                        final coverUrl = itinerary.coverImageUrl;
                        if (coverUrl != null) {
                          final absUrl = coverUrl.startsWith('/')
                              ? '$kApiBaseUrl$coverUrl'
                              : coverUrl;
                          await CachedNetworkImage.evictFromCache(absUrl);
                        }
                        await ref
                            .read(itineraryDetailProvider(widget.itineraryId)
                                .notifier)
                            .refresh();
                      },
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Stack(
                              alignment: AlignmentDirectional.topStart,
                              children: [
                                if (itinerary.coverImageUrl != null)
                                  _CoverImage(
                                    url: itinerary.coverImageUrl!
                                            .startsWith('/')
                                        ? '$kApiBaseUrl${itinerary.coverImageUrl}'
                                        : itinerary.coverImageUrl!,
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      _SummaryChip(
                                        icon: Icons.timer_outlined,
                                        label: itinerary.formattedDuration,
                                      ),
                                      _SummaryChip(
                                        icon: Icons.payments_outlined,
                                        label: itinerary.formattedCost,
                                      ),
                                      _SummaryChip(
                                        icon: Icons.place_outlined,
                                        label:
                                            '${allStops.length} stop${allStops.length == 1 ? '' : 's'}',
                                      ),
                                      if (isOwner && _editMode)
                                        GestureDetector(
                                          onTap: () => context.push(
                                              '/itineraries/${widget.itineraryId}/edit'),
                                          child: _SummaryChip(
                                            icon: itinerary.visibilityIcon,
                                            label: itinerary.visibilityLabel,
                                          ),
                                        )
                                      else
                                        _SummaryChip(
                                          icon: itinerary.visibilityIcon,
                                          label: itinerary.visibilityLabel,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (itinerary.description != null &&
                              itinerary.description!.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: InertMarkdownBody(
                                  data: itinerary.description!,
                                ),
                              ),
                            ),
                          if (itinerary.annotations.isNotEmpty || canEdit)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Annotations',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w600),
                                        ),
                                        if (canEdit) ...[
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: _addItineraryAnnotation,
                                            icon:
                                                const Icon(Icons.add, size: 16),
                                            label: const Text('Add annotation'),
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
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
                                          'No annotations yet.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: Colors.grey.shade500),
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
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
                          SliverToBoxAdapter(
                            child: canEdit
                                ? const SizedBox.shrink()
                                : _RatingSection(
                                    itineraryId: widget.itineraryId,
                                    itinerary: itinerary,
                                  ),
                          ),
                          SliverToBoxAdapter(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _mapVisible = !_mapVisible),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.map_outlined, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Map',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15)),
                                    const Spacer(),
                                    Icon(
                                        _mapVisible
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_mapVisible)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(right: 4, left: 4),
                                child: SizedBox(
                                  height: 240,
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
                                                  color: Colors.blue
                                                      .withValues(alpha: 0.6),
                                                  strokeWidth: 3,
                                                ),
                                              ],
                                            ),
                                          MarkerLayer(
                                            markers: mappableStops.map((stop) {
                                              final color =
                                                  _markerColors[stop.type] ??
                                                      Colors.grey;
                                              return Marker(
                                                point: LatLng(
                                                    stop.lat!, stop.lng!),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              3),
                                                      decoration: BoxDecoration(
                                                        color: color,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                            color: Colors.white,
                                                            width: 2),
                                                      ),
                                                      child: Icon(Icons.place,
                                                          color: Colors.white,
                                                          size: 10),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                          RichAttributionWidget(
                                            attributions: [
                                              TextSourceAttribution(
                                                  'OpenStreetMap contributors'),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Positioned(
                                        bottom: 28,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.8),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                              'Powered by OpenStreetMap',
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.black54)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: Divider(height: 1)),
                          if (tracks.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 48),
                                child: canEdit
                                    ? GestureDetector(
                                        onTap: () => context.push(
                                          '/itineraries/${widget.itineraryId}/stops/new',
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(Icons.place_outlined,
                                                size: 48,
                                                color: Colors.grey.shade400),
                                            const SizedBox(height: 12),
                                            const Text(
                                                'No stops yet. Tap + to add one.'),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          Icon(Icons.place_outlined,
                                              size: 48,
                                              color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          const Text('No stops yet.'),
                                        ],
                                      ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.only(bottom: 16),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate(
                                  buildInterleavedList(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-row card combining the community average (left) and the user's
/// star picker (right), separated by a vertical divider.
class _RatingSection extends ConsumerWidget {
  final String itineraryId;
  final Itinerary itinerary;

  const _RatingSection({
    required this.itineraryId,
    required this.itinerary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRatingAsync = ref.watch(myRatingProvider(itineraryId));
    final myRating = myRatingAsync.valueOrNull;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // ── Left: community average ──────────────────────────────────
              Expanded(
                child: InkWell(
                  onTap: () =>
                      context.push('/itineraries/$itineraryId/ratings'),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Community',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Icon(Icons.star_rounded,
                                      size: 20,
                                      color: ratingColor(
                                          itinerary.ratingAvg ?? 3)),
                                  const SizedBox(width: 4),
                                  Text(
                                    itinerary.ratingAvg != null
                                        ? itinerary.ratingAvg!
                                            .toStringAsFixed(1)
                                        : '—',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (itinerary.ratingCount > 0) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                      '${itinerary.ratingCount} ratings',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Divider ──────────────────────────────────────────────────
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 10,
                endIndent: 10,
                color: cs.outlineVariant,
              ),

              // ── Right: my rating ─────────────────────────────────────────
              Expanded(
                child: InkWell(
                  onTap: () => showRateItineraryDialog(
                    context,
                    ref,
                    itineraryId: itineraryId,
                    current: myRating,
                  ),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    child: myRatingAsync.isLoading
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                myRating != null ? 'Your rating' : 'Rate it',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: myRating != null
                                      ? cs.onSurfaceVariant
                                      : cs.primary,
                                  letterSpacing: 0.4,
                                  fontWeight: myRating == null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: List.generate(5, (i) {
                                  final filled =
                                      myRating != null && i < myRating.stars;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: Icon(
                                      filled
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      size: 22,
                                      color: filled
                                          ? ratingColor(
                                              myRating.stars.toDouble())
                                          : cs.onSurfaceVariant
                                              .withValues(alpha: 0.4),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300.withValues(alpha: 0.8),),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w500,color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatefulWidget {
  final String url;
  const _CoverImage({required this.url});

  @override
  State<_CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<_CoverImage> {
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: Colors.black,
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              body: Center(
                child: PhotoView(
                  enableRotation: true,
                  imageProvider: CachedNetworkImageProvider(widget.url),
                ),
              ),
            ),
          ),
        );
      },
      child: AspectRatio(
        aspectRatio: 1200 / 630,
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) {
            if (!_error) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _error = true);
                }
              });
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

enum _OwnerAction { editStops, editDetails, delete }
