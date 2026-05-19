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
// LOCAL BATCH + SAVE/CANCEL (Phase 2a):
//   Earlier this sheet PATCHed every drop, one stop at a time. That meant
//   the user couldn't experiment freely — every drag was already on the
//   server. The new model keeps the working order purely local:
//     - onReorder updates _local in memory; _dirty becomes true.
//     - Save  → one POST /itineraries/{id}/reorder with the full new order.
//     - Cancel → discard local changes (with a confirm dialog if _dirty).
//     - System back / scrim dismiss → same Discard-changes confirm via
//       PopScope when _dirty.
//   On a stale ETag the sheet stays open so the user can decide.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Future<void> showReorderParallelsSheet({
  required BuildContext context,
  required String itineraryId,
  required List<Stop> stops,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // isDismissible / enableDrag stay default-true; PopScope handles the
    // confirm-on-dismiss path for dirty state.
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
  late List<String> _initialOrder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _local = List.of(widget.stops);
    _initialOrder = widget.stops.map((s) => s.id).toList();
  }

  bool get _dirty {
    if (_local.length != _initialOrder.length) return true;
    for (var i = 0; i < _local.length; i++) {
      if (_local[i].id != _initialOrder[i]) return true;
    }
    return false;
  }

  String get _trackId => widget.stops.first.trackId;

  void _onReorder(int oldIndex, int newIndex) {
    if (_busy) return;
    // Flutter's quirk: when dragging downward, newIndex is reported as the
    // index AFTER removing the item, so subtract one to get the destination.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final moved = _local.removeAt(oldIndex);
      _local.insert(newIndex, moved);
    });
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    return confirmDestructiveAction(
      context: context,
      title: 'Discard changes?',
      message: 'Your reorder will not be saved.',
      confirmLabel: 'Discard',
    );
  }

  Future<void> _onCancel() async {
    final ok = await _confirmDiscardIfDirty();
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onSave() async {
    if (_busy || !_dirty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .applyReorder(
            stopOrders: {
              _trackId: _local.map((s) => s.id).toList(),
            },
          );
    } on ItineraryStaleException {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Itinerary changed elsewhere — close and reopen to see the latest order.',
          ),
        ),
      );
      return;
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
      return;
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.orderSavedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Container(
        color: kSand,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 6, 6, 4),
                  child: Text(
                    'REORDER ALTERNATIVES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                  child: Text(
                    'Drag to change which option appears first. Tap Save to apply.',
                    style: TextStyle(fontSize: 12, color: kText2),
                  ),
                ),

                // ── Draggable list inside a SectionCard ──────────────────────
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.zero,
                      itemCount: _local.length,
                      onReorder: _onReorder,
                      itemBuilder: (_, i) {
                        final stop = _local[i];
                        return Column(
                          key: ValueKey(stop.id),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (i > 0)
                              Container(height: 1, color: kBorder),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 14, 10),
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: Icon(
                                          Icons.drag_indicator_rounded,
                                          size: 20,
                                          color: kText3),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      color: kMist,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: kForest,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stop.placeName ?? '(unnamed)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: kBark,
                                          ),
                                        ),
                                        if (stop.placeAddress != null &&
                                            stop.placeAddress!.isNotEmpty)
                                          Text(
                                            stop.placeAddress!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11, color: kText2),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // ── Progress + buttons ────────────────────────────────────
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: kForest,
                      backgroundColor: kMist,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _onCancel,
                      style: TextButton.styleFrom(foregroundColor: kForest),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: (_busy || !_dirty) ? null : _onSave,
                      child: Text(AppLocalizations.of(context)!.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
