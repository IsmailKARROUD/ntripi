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
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
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

  void _showLegDetails(TransportLeg leg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _LegDetailSheet(
        leg: leg,
        currency: widget.currency,
      ),
    );
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
    final routeColor = kCanopy.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: kMist.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Route line: dot → dashed line → dot, parallel to content
                SizedBox(
                  width: 14,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: routeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: CustomPaint(
                          painter: _DashedLinePainter(color: routeColor),
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: routeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Segment content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (segment.legs.isNotEmpty) ...[
                        const SizedBox(height: 4),
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
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () =>
                                          _showLegDetails(segment.legs[i]),
                                      child: TransportBadge(
                                        leg: segment.legs[i],
                                        currency: widget.currency,
                                      ),
                                    ),
                            if (_isEditable)
                              GestureDetector(
                                onTap: _saving ? null : _addLeg,
                                child: const AddTransportBadge(),
                              ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: _saving ? null : _addLeg,
                          child: Text(
                            'No transport legs added yet. Tap to add.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_saving)
                  Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: kCanopy.withValues(alpha: 0.8),
                      ),
                    ),
                  )
                else if (widget.onDelete != null)
                  Center(
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: widget.onDelete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: kRatingRed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegDetailSheet extends StatelessWidget {
  final TransportLeg leg;
  final String currency;

  const _LegDetailSheet({
    required this.leg,
    required this.currency,
  });

  static IconData _noteTypeIcon(AnnotationType? t) => switch (t) {
        AnnotationType.caution => Icons.warning_amber_outlined,
        AnnotationType.avoid => Icons.block_outlined,
        AnnotationType.advice => Icons.lightbulb_outline,
        _ => Icons.info_outline,
      };

  static Color _noteTypeColor(AnnotationType? t) => switch (t) {
        AnnotationType.caution => kRatingOrange,
        AnnotationType.avoid => kRatingRed,
        AnnotationType.advice => kAmber,
        _ => kText2,
      };

  String get _costLabel {
    if (leg.isFree) return 'Free';
    if (leg.cost > 0) return '${leg.cost.toStringAsFixed(2)} $currency';
    return 'No cost info';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <_DetailRow>[
      _DetailRow(Icons.directions, 'Mode', leg.mode.label),
      if (leg.line != null && leg.line!.isNotEmpty)
        _DetailRow(Icons.confirmation_number_outlined, 'Line', leg.line!),
      if (leg.direction != null && leg.direction!.isNotEmpty)
        _DetailRow(Icons.arrow_forward, 'Direction', leg.direction!),
      if (leg.formattedDuration.isNotEmpty)
        _DetailRow(Icons.timer_outlined, 'Duration', leg.formattedDuration),
      _DetailRow(Icons.payments_outlined, 'Cost', _costLabel),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 8,top: 14, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Row(
                
                children: [
                  Icon(leg.mode.icon, size: 20, color: kCanopy),
                  const SizedBox(width: 8),
                  Text(
                    leg.summary.isNotEmpty ? leg.summary : leg.mode.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 5),
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(r.icon, size: 16, color: kText2),
                    const SizedBox(width: 10),
                    Text(r.label,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: kText2, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(r.value,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
            if (leg.notes != null && leg.notes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _noteTypeIcon(leg.noteType),
                    size: 16,
                    color: _noteTypeColor(leg.noteType),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(leg.notes!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: kBark)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashHeight = 3.0;
    const gapHeight = 3.0;
    double y = 0;
    final cx = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, (y + dashHeight).clamp(0, size.height)),
        paint,
      );
      y += dashHeight + gapHeight;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
