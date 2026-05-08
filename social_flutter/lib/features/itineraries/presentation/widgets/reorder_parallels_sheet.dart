// widgets/reorder_parallels_sheet.dart — Bottom sheet for reordering the
// parallel alternatives of a single track via drag-and-drop.
//
// WHY A SHEET INSTEAD OF AN INLINE REORDERABLELISTVIEW?
//   The track UI shows parallels as a horizontal swipeable PageView, so
//   reordering inline would mean swapping the entire interaction model
//   while the user is on the page. A modal sheet keeps the existing
//   browse-by-swipe affordance intact and gives the reorder gesture a
//   clear scope (you're explicitly editing order while it's open).
//
// OPTIMISTIC UPDATE:
//   The sheet keeps a local copy of the parallel list. Each drop:
//     1. Updates the local list immediately (visual feedback).
//     2. Computes the moved stop's new neighbours and PATCHes the server.
//     3. On success: the parent provider refreshes (server-confirmed ranks).
//     4. On failure: shows a snackbar and rolls the local list back to the
//        last server-confirmed order.
//
//   We do not wait between drops — concurrent drops would interleave PATCH
//   calls. ETag/If-Match handles that: a second PATCH against a stale ETag
//   returns 412 → ItineraryStaleException → user is prompted to reload.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

Future<void> showReorderParallelsSheet({
  required BuildContext context,
  required String itineraryId,
  required List<Stop> stops,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReorderParallelsSheet(
      itineraryId: itineraryId,
      stops: stops,
    ),
  );
}

class _ReorderParallelsSheet extends ConsumerStatefulWidget {
  final String itineraryId;
  final List<Stop> stops;

  const _ReorderParallelsSheet({
    required this.itineraryId,
    required this.stops,
  });

  @override
  ConsumerState<_ReorderParallelsSheet> createState() =>
      _ReorderParallelsSheetState();
}

class _ReorderParallelsSheetState
    extends ConsumerState<_ReorderParallelsSheet> {
  late List<Stop> _local;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _local = List.of(widget.stops);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_busy) return;
    // Flutter's quirk: when dragging downward, newIndex is reported as the
    // index AFTER removing the item, so subtract one to get the destination.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final previous = List.of(_local);
    setState(() {
      final moved = _local.removeAt(oldIndex);
      _local.insert(newIndex, moved);
      _busy = true;
    });

    final movedStop = _local[newIndex];
    final afterStopId =
        newIndex > 0 ? _local[newIndex - 1].id : null;
    final beforeStopId =
        newIndex < _local.length - 1 ? _local[newIndex + 1].id : null;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .moveStop(
            movedStop.id,
            afterStopId: afterStopId,
            beforeStopId: beforeStopId,
          );
      if (!mounted) return;
      // Adopt the server's authoritative order for this track.
      final fresh = ref
          .read(itineraryDetailProvider(widget.itineraryId))
          .valueOrNull;
      if (fresh != null) {
        final track = fresh.tracks.firstWhere(
          (t) => t.id == movedStop.trackId,
          orElse: () => fresh.tracks.first,
        );
        setState(() => _local = List.of(track.stops));
      }
    } on ItineraryStaleException {
      if (!mounted) return;
      setState(() => _local = previous);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Itinerary changed elsewhere — close and reopen to see the latest order.',
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _local = previous);
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reorder alternatives',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Drag to change which option appears first when the track is viewed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _local.length,
                onReorder: _onReorder,
                itemBuilder: (_, i) {
                  final stop = _local[i];
                  return ListTile(
                    key: ValueKey(stop.id),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      stop.placeName ?? '(unnamed)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: stop.placeAddress != null
                        ? Text(
                            stop.placeAddress!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          )
                        : null,
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
