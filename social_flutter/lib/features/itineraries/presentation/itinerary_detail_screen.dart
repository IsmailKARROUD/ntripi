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
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/segment_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class ItineraryDetailScreen extends ConsumerStatefulWidget {
  final String itineraryId;

  const ItineraryDetailScreen({super.key, required this.itineraryId});

  @override
  ConsumerState<ItineraryDetailScreen> createState() =>
      _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends ConsumerState<ItineraryDetailScreen> {
  bool _editMode = false;
  // Reorder mode replaces the interleaved list with a standalone
  // ReorderableListView so drag gestures aren't stolen by CustomScrollView.
  bool _reorderMode = false;
  bool _saving = false;
  bool _mapVisible = true;
  // Captured on edit-mode entry; compared on exit to detect unsaved reorders.
  List<String> _originalStopOrder = [];
  // Null = no drag has happened yet (provider order is authoritative).
  // Non-null = user dragged at least once; this order is rendered locally
  // until the user saves (sends to server) or discards.
  List<String>? _pendingOrder;

  static const _markerColors = {
    StopType.origin: Colors.green,
    StopType.waypoint: Colors.blue,
    StopType.arrival: Colors.red,
  };

  void _enterEditMode(List<Stop> stops) {
    setState(() {
      _editMode = true;
      _originalStopOrder = stops.map((s) => s.id).toList();
      _pendingOrder = null;
    });
  }

  // Re-orders providerStops according to _pendingOrder.
  // We always use the fresh provider objects (not stale snapshots) so that
  // edits made in sub-screens (place name, cost…) are reflected immediately.
  List<Stop> _applyPendingOrder(List<Stop> providerStops) {
    if (_pendingOrder == null) return providerStops;
    final map = {for (final s in providerStops) s.id: s};
    final ordered =
        _pendingOrder!.map((id) => map[id]).whereType<Stop>().toList();
    // Stops added from sub-screens while in edit mode won't be in _pendingOrder
    // yet — append them at the end so they're never invisible.
    for (final s in providerStops) {
      if (!_pendingOrder!.contains(s.id)) ordered.add(s);
    }
    return ordered;
  }

  // Keeps _pendingOrder consistent when sub-screens add or delete stops.
  // Uses addPostFrameCallback because this is called from ref.listen, which
  // fires during the provider's build phase — calling setState directly there
  // would schedule a rebuild inside a rebuild and trigger an assertion.
  void _syncPendingOrder(List<Stop> providerStops) {
    if (_pendingOrder == null) return;
    final newIds = providerStops.map((s) => s.id).toSet();
    final synced = [
      ..._pendingOrder!.where(newIds.contains), // keep existing, drop deleted
      ...newIds.where((id) => !_pendingOrder!.contains(id)), // append new
    ];
    if (!_listsEqual(synced, _pendingOrder!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pendingOrder = synced);
      });
    }
  }

  // Records the new order locally without touching the server.
  // ReorderableListView passes newIndex AFTER removal, so we decrement when
  // moving downward to get the correct insertion index.
  void _onReorder(List<Stop> displayStops, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final ids = displayStops.map((s) => s.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _pendingOrder = ids);
  }

  // Only stop reordering is "pending" — every other mutation (stop edit/delete,
  // segment edit/delete, add stop) commits immediately via the sub-screen.
  bool get _hasChanges =>
      _pendingOrder != null && !_listsEqual(_pendingOrder!, _originalStopOrder);

  /// Save pending reorder to the server and exit edit mode.
  Future<void> _saveAndExit() async {
    setState(() => _saving = true);
    try {
      if (_hasChanges) {
        await ref
            .read(itineraryDetailProvider(widget.itineraryId).notifier)
            .reorderStops(_pendingOrder!);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
      setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editMode = false;
      _reorderMode = false;
      _pendingOrder = null;
    });
  }

  /// Called by the back button when in edit mode with unsaved changes.
  /// Shows Stay / Discard / Save.
  Future<void> _confirmExitEditMode() async {
    final result = await showDialog<_ExitAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes. What do you want to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ExitAction.stay),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ExitAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_ExitAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == _ExitAction.save) {
      await _saveAndExit();
    } else if (result == _ExitAction.discard) {
      setState(() {
        _editMode = false;
        _reorderMode = false;
        _pendingOrder = null;
      });
    }
    // _ExitAction.stay → do nothing, stay in edit mode.
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
      title: 'Delete note?',
      message: 'This will permanently remove this note from the itinerary.',
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
      message: 'This will permanently remove this note.',
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

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(widget.itineraryId));
    final currentUserId = ref.watch(myProfileProvider).valueOrNull?.id;
    final isOwner = currentUserId != null &&
        itineraryAsync.valueOrNull?.userId == currentUserId;

    // Keep _pendingOrder in sync when sub-screens add or delete stops.
    ref.listen(itineraryDetailProvider(widget.itineraryId), (_, next) {
      _syncPendingOrder(next.valueOrNull?.stops ?? []);
    });

    return PopScope(
      canPop: !_editMode,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_hasChanges) {
          await _confirmExitEditMode();
        } else {
          setState(() {
            _editMode = false;
            _reorderMode = false;
            _pendingOrder = null;
          });
        }
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: itineraryAsync.when(
                data: (i) => Text(i.title),
                loading: () => const Text('Loading...'),
                error: (_, __) => const Text('Itinerary'),
              ),
              actions: [
                if (isOwner && _editMode) ...[
                  IconButton(
                    icon: const Icon(Icons.add_location_alt_outlined),
                    tooltip: 'Add stop',
                    onPressed: _reorderMode
                        ? null
                        : () => context.push(
                              '/itineraries/${widget.itineraryId}/stops/new',
                            ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.directions_transit_outlined),
                    tooltip: 'Add segment',
                    onPressed: _reorderMode
                        ? null
                        : () => context.push(
                              '/itineraries/${widget.itineraryId}/segments/new',
                            ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.reorder,
                      color: _reorderMode
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    tooltip: _reorderMode ? 'Exit reorder' : 'Reorder stops',
                    onPressed: () =>
                        setState(() => _reorderMode = !_reorderMode),
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
                            _enterEditMode(
                                itineraryAsync.valueOrNull?.stops ?? []);
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
                              router.go('/');
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
                constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
              child: _reorderMode
                  ? itineraryAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text(extractErrorMessage(e as dynamic))),
                      data: (itinerary) {
                        final displayStops = _applyPendingOrder(itinerary.stops);
                        final stopWidgets = displayStops
                            .map((stop) => StopCard(
                                  key: ValueKey(stop.id),
                                  stop: stop,
                                  currency: itinerary.currency,
                                ))
                            .toList();
                        return ReorderableListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          onReorder: (oldIndex, newIndex) =>
                              _onReorder(displayStops, oldIndex, newIndex),
                          children: stopWidgets,
                        );
                      },
                    )
                  : itineraryAsync.when(
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
                                  .read(
                                      itineraryDetailProvider(widget.itineraryId)
                                          .notifier)
                                  .refresh(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                      data: (itinerary) {
                        final displayStops = _applyPendingOrder(itinerary.stops);
              
                        // Build a lookup from fromStopId → segment for interleaved display.
                        final segmentByFromStop = {
                          for (final seg in itinerary.segments)
                            seg.fromStopId: seg,
                        };
                        final stopById = {
                          for (final s in itinerary.stops) s.id: s
                        };
              
                        final mappableStops = displayStops
                            .where((s) => s.lat != null && s.lng != null)
                            .toList();
              
                        final polylinePoints = mappableStops
                            .map((s) => LatLng(s.lat!, s.lng!))
                            .toList();
              
                        final mapCenter = mappableStops.isNotEmpty
                            ? LatLng(mappableStops.first.lat!,
                                mappableStops.first.lng!)
                            : const LatLng(48.8566, 2.3522);
              
                        final canEdit = isOwner && _editMode;
              
                        final stopWidgets = displayStops.map((stop) {
                          return StopCard(
                            key: ValueKey(stop.id),
                            stop: stop,
                            currency: itinerary.currency,
                            onEdit: canEdit
                                ? () => context.push(
                                      '/itineraries/${widget.itineraryId}/stops/${stop.id}/edit',
                                    )
                                : null,
                          );
                        }).toList();
              
                        // Interleaved list: StopCard, then optional SegmentCard after each stop.
                        // For a single stop, contextual "Add stop" buttons appear above/below
                        // depending on the stop's role (origin/waypoint/arrival).
                        List<Widget> buildInterleavedList() {
                          final items = <Widget>[];
                          final isOnlyStop = displayStops.length == 1;
              
                          for (var i = 0; i < displayStops.length; i++) {
                            final stop = displayStops[i];
                            final hasNextStop = i < displayStops.length - 1;
              
                            // Single-stop: "Add stop" above for waypoint or arrival.
                            if (canEdit &&
                                isOnlyStop &&
                                stop.type != StopType.origin) {
                              items.add(_InlineSeparator(
                                key: ValueKey('above-${stop.id}'),
                                onAddStop: () => context.push(
                                  '/itineraries/${widget.itineraryId}/stops/new',
                                  extra: {
                                    'insertAfterPosition': stop.position - 1
                                  },
                                ),
                              ));
                            }
              
                            items.add(StopCard(
                              key: ValueKey('stop-${stop.id}'),
                              stop: stop,
                              currency: itinerary.currency,
                              onEdit: canEdit
                                  ? () => context.push(
                                        '/itineraries/${widget.itineraryId}/stops/${stop.id}/edit',
                                      )
                                  : null,
                              onAddAnnotation: canEdit
                                  ? () => _addAnnotation(stop.id)
                                  : null,
                              onEditAnnotation: canEdit
                                  ? (a) => _editAnnotation(stop.id, a)
                                  : null,
                              onDeleteAnnotation: canEdit
                                  ? (a) => _deleteAnnotation(stop.id, a)
                                  : null,
                            ));
              
                            final seg = segmentByFromStop[stop.id];
              
                            if (seg != null) {
                              items.add(SegmentCard(
                                key: ValueKey('seg-${seg.id}'),
                                segment: seg,
                                currency: itinerary.currency,
                                fromStopName: stopById[seg.fromStopId]?.placeName,
                                toStopName: stopById[seg.toStopId]?.placeName,
                                onEdit: canEdit
                                    ? () => context.push(
                                          '/itineraries/${widget.itineraryId}/segments/${seg.id}/edit',
                                        )
                                    : null,
                                onDelete: canEdit
                                    ? () => _confirmDeleteSegment(seg)
                                    : null,
                              ));
                            }
              
                            if (canEdit) {
                              if (hasNextStop) {
                                // 2+ stops: inline separator with "Add stop" and optional "Add segment".
                                final nextStop = displayStops[i + 1];
                                items.add(_InlineSeparator(
                                  key: ValueKey('sep-${stop.id}'),
                                  onAddStop: () => context.push(
                                    '/itineraries/${widget.itineraryId}/stops/new',
                                    extra: {'insertAfterPosition': stop.position},
                                  ),
                                  onAddSegment: seg == null
                                      ? () => context.push(
                                            '/itineraries/${widget.itineraryId}/segments/new',
                                            extra: {
                                              'fromStopId': stop.id,
                                              'toStopId': nextStop.id,
                                            },
                                          )
                                      : null,
                                ));
                              } else if (stop.type != StopType.arrival) {
                                // Last stop: "Add stop" below for origin or waypoint.
                                items.add(_InlineSeparator(
                                  key: ValueKey('below-${stop.id}'),
                                  onAddStop: () => context.push(
                                    '/itineraries/${widget.itineraryId}/stops/new',
                                    extra: {'insertAfterPosition': stop.position},
                                  ),
                                ));
                              }
                            }
                          }
                          return items;
                        }
              
                        return RefreshIndicator(
                          onRefresh: () => ref
                              .read(itineraryDetailProvider(widget.itineraryId)
                                  .notifier)
                              .refresh(),
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              // ------------------------------------------------------------
                              // Cover image hero banner
                              // ------------------------------------------------------------
                              if (itinerary.coverImageUrl != null)
                                SliverToBoxAdapter(
                                  child: _CoverImage(
                                    url: itinerary.coverImageUrl!.startsWith('/')
                                        ? '$kApiBaseUrl${itinerary.coverImageUrl}'
                                        : itinerary.coverImageUrl!,
                                  ),
                                ),
              
                              // ------------------------------------------------------------
                              // Summary chips
                              // ------------------------------------------------------------
                              SliverToBoxAdapter(
                                child: Padding(
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
                                            '${displayStops.length} stop${displayStops.length == 1 ? '' : 's'}',
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
                              ),
              
                              // ------------------------------------------------------------
                              // Description
                              // ------------------------------------------------------------
                              if (itinerary.description != null &&
                                  itinerary.description!.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Text(
                                      itinerary.description!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.grey.shade700),
                                    ),
                                  ),
                                ),
              
                              // ------------------------------------------------------------
                              // Itinerary-level annotations (Notes)
                              // ------------------------------------------------------------
                              if (itinerary.annotations.isNotEmpty || canEdit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 10, 16, 4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Notes',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            if (canEdit) ...[
                                              const Spacer(),
                                              TextButton.icon(
                                                onPressed:
                                                    _addItineraryAnnotation,
                                                icon: const Icon(Icons.add,
                                                    size: 16),
                                                label: const Text('Add note'),
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
                                              'No notes yet.',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        Colors.grey.shade500,
                                                  ),
                                            ),
                                          )
                                        else
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6),
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

                              // ------------------------------------------------------------
                              // Rating section (read) / Save button (edit mode)
                              // ------------------------------------------------------------
                              SliverToBoxAdapter(
                                child: canEdit
                                    ? Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            64, 10, 64, 10),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            onPressed:
                                                _saving ? null : _saveAndExit,
                                            child: _saving
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: kSand,
                                                    ),
                                                  )
                                                : const Text(
                                                    'Save',
                                                    style: TextStyle(
                                                      color: kSand,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 20,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      )
                                    : _RatingSection(
                                        itineraryId: widget.itineraryId,
                                        itinerary: itinerary,
                                      ),
                              ),
              
                              // ------------------------------------------------------------
                              // Map section
                              // ------------------------------------------------------------
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
                                        const Text(
                                          'Map',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          _mapVisible
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 20,
                                        ),
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
                                                mappableStops.isNotEmpty
                                                    ? 12
                                                    : 5,
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
                                                        .withOpacity(0.6),
                                                    strokeWidth: 3,
                                                  ),
                                                ],
                                              ),
                                            MarkerLayer(
                                              markers:
                                                  mappableStops.map((stop) {
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
                                                            const EdgeInsets
                                                                .all(3),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: color,
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                            color: Colors.white,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '${stop.position}',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                            RichAttributionWidget(
                                              attributions: [
                                                TextSourceAttribution(
                                                  'OpenStreetMap contributors',
                                                ),
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
                                              color:
                                                  Colors.white.withOpacity(0.8),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Powered by OpenStreetMap',
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.black54),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
              
                              const SliverToBoxAdapter(child: Divider(height: 1)),
              
                              // ------------------------------------------------------------
                              // Stop list (edit: reorderable stops only; read: interleaved)
                              // ------------------------------------------------------------
                              if (displayStops.isEmpty)
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
                              else if (_reorderMode)
                                SliverToBoxAdapter(
                                  child: ReorderableListView(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(bottom: 16),
                                    onReorder: (oldIndex, newIndex) => _onReorder(
                                        displayStops, oldIndex, newIndex),
                                    children: stopWidgets,
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
                                      size: 20, color: ratingColor(itinerary.ratingAvg ?? 3)),
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
                                          ? ratingColor(myRating.stars.toDouble())
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _InlineSeparator extends StatelessWidget {
  final VoidCallback onAddStop;
  final VoidCallback? onAddSegment;

  const _InlineSeparator({
    super.key,
    required this.onAddStop,
    this.onAddSegment,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.add_location_alt_outlined,
            label: 'Add stop',
            onTap: onAddStop,
          ),
          if (onAddSegment != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ),
            _ActionButton(
              icon: Icons.directions_transit_outlined,
              label: 'Segment',
              onTap: onAddSegment!,
            ),
          ],
          const SizedBox(width: 8),
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade500),
            ),
          ],
        ),
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
    if (_error) return const SizedBox.shrink();
    return AspectRatio(
      aspectRatio: 1200 / 630,
      child: Image.network(
        widget.url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _error = true);
          });
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

enum _ExitAction { stay, discard, save }

enum _OwnerAction { editStops, editDetails, delete }
