// presentation/itinerary_detail_screen.dart — Full itinerary view with map.
//
// Layout (all inside one CustomScrollView so pull-to-refresh works anywhere):
//   AppBar — title + edit action
//   Summary chips — duration, cost, safety rating, stop count
//   Description (optional)
//   Rating section — community avg + user's star picker
//   Map section — flutter_map with stop markers and connecting polyline
//   Stop list — ReorderableListView (owner) or plain list (others)
//   FAB — navigate to StopFormScreen (owner only)
//
// OSM attribution is required by the ODbL license and is always visible.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/segment_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class ItineraryDetailScreen extends ConsumerStatefulWidget {
  final String itineraryId;

  const ItineraryDetailScreen({super.key, required this.itineraryId});

  @override
  ConsumerState<ItineraryDetailScreen> createState() =>
      _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState
    extends ConsumerState<ItineraryDetailScreen> {
  bool _editMode = false;
  bool _saving = false;
  // Snapshot of stop IDs when edit mode was entered — used to detect changes.
  List<String> _originalStopOrder = [];
  // Local pending order: non-null only after the user drags at least once.
  List<String>? _pendingOrder;

  static const _markerColors = {
    StopType.origin: Colors.green,
    StopType.waypoint: Colors.blue,
    StopType.destination: Colors.red,
  };

  void _enterEditMode(List<Stop> stops) {
    setState(() {
      _editMode = true;
      _originalStopOrder = stops.map((s) => s.id).toList();
      _pendingOrder = null;
    });
  }

  // Sorts provider stops by the pending order, keeping content always fresh.
  List<Stop> _applyPendingOrder(List<Stop> providerStops) {
    if (_pendingOrder == null) return providerStops;
    final map = {for (final s in providerStops) s.id: s};
    final ordered = _pendingOrder!
        .map((id) => map[id])
        .whereType<Stop>()
        .toList();
    // Append any new stops (added from a sub-screen) at the end.
    for (final s in providerStops) {
      if (!_pendingOrder!.contains(s.id)) ordered.add(s);
    }
    return ordered;
  }

  // Sync _pendingOrder when stops are added/deleted from sub-screens.
  void _syncPendingOrder(List<Stop> providerStops) {
    if (_pendingOrder == null) return;
    final newIds = providerStops.map((s) => s.id).toSet();
    final synced = [
      ..._pendingOrder!.where(newIds.contains),
      ...newIds.where((id) => !_pendingOrder!.contains(id)),
    ];
    if (!_listsEqual(synced, _pendingOrder!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pendingOrder = synced);
      });
    }
  }

  // Local-only reorder — no API call. Deferred until Save.
  void _onReorder(List<Stop> displayStops, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final ids = displayStops.map((s) => s.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _pendingOrder = ids);
  }

  Future<void> _confirmExitEditMode() async {
    final hasReordered = _pendingOrder != null &&
        !_listsEqual(_pendingOrder!, _originalStopOrder);

    final result = await showDialog<_ExitAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit edit mode?'),
        content: Text(
          hasReordered
              ? 'You reordered stops. Save or discard the new order?'
              : 'Do you want to exit edit mode?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ExitAction.stay),
            child: const Text('Stay'),
          ),
          if (hasReordered)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_ExitAction.discard),
              child: const Text('Discard'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_ExitAction.save),
            child: Text(hasReordered ? 'Save' : 'Exit'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == _ExitAction.save && hasReordered) {
      setState(() => _saving = true);
      try {
        await ref
            .read(itineraryDetailProvider(widget.itineraryId).notifier)
            .reorderStops(_pendingOrder!);
      } on Exception catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e as dynamic))),
        );
        setState(() => _saving = false);
        return;
      }
      if (!mounted) return;
      setState(() => _saving = false);
    }

    // Discard: just drop local state — no API call needed.
    if (result == _ExitAction.save || result == _ExitAction.discard) {
      setState(() {
        _editMode = false;
        _pendingOrder = null;
      });
    }
  }

  Future<void> _confirmDeleteSegment(TransitSegment segment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete segment?'),
        content: const Text('This will remove the transit segment and all its legs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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

    return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        title: itineraryAsync.when(
          data: (i) => Text(i.title),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Itinerary'),
        ),
        actions: [
          if (isOwner)
            IconButton(
              icon: Icon(_editMode ? Icons.close : Icons.edit_outlined),
              tooltip: _editMode ? 'Exit edit mode' : 'Edit',
              onPressed: _editMode
                  ? _confirmExitEditMode
                  : () => _enterEditMode(
                        itineraryAsync.valueOrNull?.stops ?? [],
                      ),
            ),
        ],
      ),
      body: itineraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                    .read(itineraryDetailProvider(widget.itineraryId).notifier)
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
            for (final seg in itinerary.segments) seg.fromStopId: seg,
          };
          final stopById = {for (final s in itinerary.stops) s.id: s};

          final mappableStops = displayStops
              .where((s) => s.lat != null && s.lng != null)
              .toList();

          final polylinePoints = mappableStops
              .map((s) => LatLng(s.lat!, s.lng!))
              .toList();

          final mapCenter = mappableStops.isNotEmpty
              ? LatLng(mappableStops.first.lat!, mappableStops.first.lng!)
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
          List<Widget> buildInterleavedList() {
            final items = <Widget>[];
            for (var i = 0; i < displayStops.length; i++) {
              final stop = displayStops[i];
              items.add(StopCard(
                key: ValueKey('stop-${stop.id}'),
                stop: stop,
                currency: itinerary.currency,
                onEdit: canEdit
                    ? () => context.push(
                          '/itineraries/${widget.itineraryId}/stops/${stop.id}/edit',
                        )
                    : null,
              ));

              final seg = segmentByFromStop[stop.id];
              final hasNextStop = i < displayStops.length - 1;

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
                  onDelete: canEdit ? () => _confirmDeleteSegment(seg) : null,
                ));
              } else if (canEdit && hasNextStop) {
                final nextStop = displayStops[i + 1];
                items.add(_AddSegmentRow(
                  key: ValueKey('add-seg-${stop.id}'),
                  onTap: () => context.push(
                    '/itineraries/${widget.itineraryId}/segments/new',
                    extra: {
                      'fromStopId': stop.id,
                      'toStopId': nextStop.id,
                    },
                  ),
                ));
              }
            }
            return items;
          }

          return RefreshIndicator(
            onRefresh: () => ref
                .read(itineraryDetailProvider(widget.itineraryId).notifier)
                .refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
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
                        if (itinerary.safetyRating != null)
                          _SummaryChip(
                            icon: Icons.star,
                            label: '${itinerary.safetyRating}/5',
                            iconColor: Colors.amber,
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                // Rating section
                // ------------------------------------------------------------
                SliverToBoxAdapter(
                  child: _RatingSection(
                    itineraryId: widget.itineraryId,
                    itinerary: itinerary,
                  ),
                ),

                // ------------------------------------------------------------
                // Map section
                // ------------------------------------------------------------
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 240,
                    child: Stack(
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: mapCenter,
                            initialZoom: mappableStops.isNotEmpty ? 12 : 5,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.ntripi.app',
                            ),
                            if (polylinePoints.length >= 2)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: polylinePoints,
                                    color: Colors.blue.withOpacity(0.6),
                                    strokeWidth: 3,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: mappableStops.map((stop) {
                                final color =
                                    _markerColors[stop.type] ?? Colors.grey;
                                return Marker(
                                  point: LatLng(stop.lat!, stop.lng!),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                        child: Text(
                                          '${stop.position}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
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
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Powered by OpenStreetMap',
                              style: TextStyle(
                                  fontSize: 9, color: Colors.black54),
                            ),
                          ),
                        ),
                      ],
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
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(canEdit
                              ? 'No stops yet. Tap + to add one.'
                              : 'No stops yet.'),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: canEdit ? 100 : 16),
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
      floatingActionButton: isOwner && _editMode
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab_segment',
                  tooltip: 'Add Segment',
                  onPressed: () => context.push(
                      '/itineraries/${widget.itineraryId}/segments/new'),
                  child: const Icon(Icons.directions_transit_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'fab_stop',
                  tooltip: 'Add Stop',
                  onPressed: () => context
                      .push('/itineraries/${widget.itineraryId}/stops/new'),
                  child: const Icon(Icons.add),
                ),
              ],
            )
          : null,
        ),
        // Saving overlay — shown while the single reorder API call is in flight.
        if (_saving)
          const ColoredBox(
            color: Color(0x66000000),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

/// Shows the community rating average + the current user's star picker.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable row → navigates to the full ratings page.
          InkWell(
            onTap: () =>
                context.push('/itineraries/$itineraryId/ratings'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    itinerary.ratingAvg != null
                        ? '${itinerary.ratingAvg!.toStringAsFixed(1)} / 5'
                        : 'No ratings yet',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (itinerary.ratingCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(${itinerary.ratingCount})',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 16, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          myRatingAsync.when(
            loading: () => const SizedBox(height: 28),
            error: (_, __) => const SizedBox.shrink(),
            data: (myStars) => _StarPicker(
              itineraryId: itineraryId,
              currentStars: myStars,
            ),
          ),
        ],
      ),
    );
  }
}

/// Five tappable stars for submitting / updating a rating.
class _StarPicker extends ConsumerWidget {
  final String itineraryId;
  final int? currentStars;

  const _StarPicker({required this.itineraryId, this.currentStars});

  Future<void> _onTap(WidgetRef ref, BuildContext context, int stars) async {
    try {
      if (currentStars == stars) {
        await ref.read(myRatingProvider(itineraryId).notifier).deleteRating();
      } else {
        await ref
            .read(myRatingProvider(itineraryId).notifier)
            .submitRating(stars);
      }
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final star = index + 1;
        final filled = currentStars != null && star <= currentStars!;
        return GestureDetector(
          onTap: () => _onTap(ref, context, star),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 28,
              color: filled ? Colors.amber : Colors.grey.shade400,
            ),
          ),
        );
      }),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const _SummaryChip({required this.icon, required this.label, this.iconColor});

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
          Icon(icon, size: 14, color: iconColor ?? Colors.grey.shade600),
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

class _AddSegmentRow extends StatelessWidget {
  final VoidCallback onTap;

  const _AddSegmentRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
              const SizedBox(width: 8),
              Icon(Icons.add, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                'Add segment',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ExitAction { stay, discard, save }
