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
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
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

  static const _markerColors = {
    StopType.origin: Colors.green,
    StopType.waypoint: Colors.blue,
    StopType.transit: Colors.grey,
    StopType.destination: Colors.red,
  };

  Future<void> _onReorder(
    List<Stop> stops,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;

    final reordered = [...stops];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final stopIds = reordered.map((s) => s.id).toList();
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .reorderStops(stopIds);
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

    return Scaffold(
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
              onPressed: () => setState(() => _editMode = !_editMode),
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
          final mappableStops = itinerary.stops
              .where((s) => s.lat != null && s.lng != null)
              .toList();

          final polylinePoints = mappableStops
              .map((s) => LatLng(s.lat!, s.lng!))
              .toList();

          final mapCenter = mappableStops.isNotEmpty
              ? LatLng(mappableStops.first.lat!, mappableStops.first.lng!)
              : const LatLng(48.8566, 2.3522);

          final canEdit = isOwner && _editMode;

          // Build the stop list as a plain list of widgets so we can put it
          // inside a SliverList. The ReorderableListView is placed in a
          // SliverToBoxAdapter with shrinkWrap so it sizes to its content.
          final stopWidgets = itinerary.stops.map((stop) {
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
                              '${itinerary.stops.length} stop${itinerary.stops.length == 1 ? '' : 's'}',
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
                // Stop list
                // ------------------------------------------------------------
                if (itinerary.stops.isEmpty)
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
                else if (canEdit)
                  // ReorderableListView must be shrinkWrapped inside a
                  // SliverToBoxAdapter so the outer CustomScrollView scrolls.
                  SliverToBoxAdapter(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 80),
                      onReorder: (oldIndex, newIndex) => _onReorder(
                        itinerary.stops,
                        oldIndex,
                        newIndex,
                      ),
                      children: stopWidgets,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => stopWidgets[index],
                        childCount: stopWidgets.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: isOwner && _editMode
          ? FloatingActionButton(
              onPressed: () => context
                  .push('/itineraries/${widget.itineraryId}/stops/new'),
              child: const Icon(Icons.add),
            )
          : null,
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
