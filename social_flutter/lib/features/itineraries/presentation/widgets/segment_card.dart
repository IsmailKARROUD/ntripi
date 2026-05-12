// widgets/segment_card.dart — Card showing a transit segment between two stops.
//
// Rendered inside buildInterleavedList() in itinerary_detail_screen.dart.
// The horizontal padding (36) intentionally indents it relative to StopCards
// so it looks visually nested between them.
// onEdit / onDelete are null in read-only mode; non-null in edit mode.
//
// In edit mode the card supports inline leg management:
//   - Tap any badge to edit that leg via LegFormDialog.
//   - Tap the "+" button to add a new leg.
// Each action PATCHes the segment and refreshes via itineraryDetailProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/transport_badge.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class SegmentCard extends ConsumerStatefulWidget {
  final TransitSegment segment;
  final String currency;
  final String itineraryId;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SegmentCard({
    super.key,
    required this.segment,
    required this.currency,
    required this.itineraryId,
    this.onEdit,
    this.onDelete,
  });

  @override
  ConsumerState<SegmentCard> createState() => _SegmentCardState();
}

class _SegmentCardState extends ConsumerState<SegmentCard> {
  bool _saving = false;

  // Presence of onEdit is the canonical signal for edit mode — no separate bool needed.
  bool get _isEditable => widget.onEdit != null;

  // Converts a domain leg to the raw map format the PATCH endpoint expects.
  // Null fields are omitted so the backend doesn't overwrite them with nulls.
  Map<String, dynamic> _legToMap(TransportLeg leg) => {
        'mode': leg.mode.name,
        if (leg.line != null) 'line': leg.line,
        if (leg.direction != null) 'direction': leg.direction,
        if (leg.notes != null) 'notes': leg.notes,
        if (leg.durationMin != null) 'duration_min': leg.durationMin,
        'is_free': leg.isFree,
        'cost': leg.cost,
      };

  // Positions are always re-assigned from scratch (1-based) so order in the
  // list is the single source of truth — no stale position values leak through.
  Map<String, dynamic> _buildPayload(List<Map<String, dynamic>> legMaps) => {
        'from_stop_id': widget.segment.fromStopId,
        'to_stop_id': widget.segment.toStopId,
        'legs': [
          for (var i = 0; i < legMaps.length; i++)
            {...legMaps[i], 'position': i + 1},
        ],
      };

  // Every leg change (add / edit / delete) goes through a full-replace PATCH —
  // there are no individual leg endpoints, so we always send the complete list.
  Future<void> _saveLegs(List<Map<String, dynamic>> updatedLegs) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateSegment(widget.segment.id, _buildPayload(updatedLegs));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLeg() async {
    final result = await LegFormDialog.show(context);
    if (result == null || !mounted) return;
    await _saveLegs([...widget.segment.legs.map(_legToMap), result]);
  }

  Future<void> _editLeg(int index) async {
    final leg = widget.segment.legs[index];
    final result = await LegFormDialog.show(context, existing: leg);
    if (result == null || !mounted) return;
    // LegFormDialog signals deletion via a sentinel map instead of a separate
    // return type so the Future<Map?> signature stays unchanged.
    if (result['__action'] == 'delete') {
      // A segment with zero legs is invalid — redirect the user to delete
      // the whole segment rather than leaving an empty shell.
      if (widget.segment.legs.length == 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'A segment needs at least one leg. Delete the segment instead.'),
          ),
        );
        return;
      }
      await _saveLegs([
        for (var i = 0; i < widget.segment.legs.length; i++)
          if (i != index) _legToMap(widget.segment.legs[i]),
      ]);
      return;
    }
    await _saveLegs([
      for (var i = 0; i < widget.segment.legs.length; i++)
        i == index ? result : _legToMap(widget.segment.legs[i]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.segment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_transit_outlined,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const Spacer(),
                  if (_saving)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  if (widget.onDelete != null && !_saving) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: widget.onDelete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.red.shade400,
                    ),
                  ],
                ],
              ),
              if (segment.legs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < segment.legs.length; i++)
                      _isEditable
                          ? GestureDetector(
                              onTap: _saving ? null : () => _editLeg(i),
                              child: TransportBadge(
                                leg: segment.legs[i],
                                currency: widget.currency,
                                formattedDuration: segment.formattedDuration,
                              ),
                            )
                          : TransportBadge(
                              leg: segment.legs[i],
                              currency: widget.currency,
                              formattedDuration: segment.formattedDuration,
                            ),
                    if (_isEditable)
                      GestureDetector(
                        onTap: _saving ? null : _addLeg,
                        child: const AddTransportBadge(),
                      ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _saving ? null : _addLeg,
                  child: Text(
                    'No transport legs added yet. Tap to add.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
