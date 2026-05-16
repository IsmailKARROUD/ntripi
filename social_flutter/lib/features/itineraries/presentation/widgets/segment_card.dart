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
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
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

    // Read mode: compact amber transit row matching the design.
    if (!_isEditable) return _TransitRow(segment: segment, currency: widget.currency);

    // Edit mode: amber editorial container with tappable leg rows.
    const bgColor = Color(0xFFFFF8EC);
    const borderColor = Color(0xFFF0E2C2);
    const iconColor = Color(0xFFA06D1F);
    const textColor = Color(0xFF8A5A18);

    String fmtCost(double cost, bool isFree) {
      if (isFree || cost <= 0) return 'Free';
      return '${cost.toStringAsFixed(0)} ${widget.currency}';
    }

    String fmtMin(int? m) {
      if (m == null || m <= 0) return '';
      final h = m ~/ 60;
      final min = m % 60;
      if (h == 0) return '${min}min';
      if (min == 0) return '${h}h';
      return '${h}h ${min}min';
    }

    final legs = segment.legs;
    final multiLeg = legs.length > 1;

    final totalDur =
        segment.totalDurationMin > 0 ? fmtMin(segment.totalDurationMin) : '';
    final totalCost = segment.totalCost <= 0
        ? 'Free'
        : '${segment.totalCost.toStringAsFixed(0)} ${widget.currency}';

    return Container(
      margin: const EdgeInsets.fromLTRB(28, 6, 28, 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: label + spinner / delete ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                const Text(
                  'TRANSIT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (_saving)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: iconColor,
                    ),
                  )
                else if (widget.onDelete != null)
                  GestureDetector(
                    onTap: widget.onDelete,
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: kRatingRed),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: borderColor),

          // ── Leg rows (tappable to edit) ────────────────────────────────────
          if (legs.isEmpty)
            InkWell(
              onTap: _saving ? null : _addLeg,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Text(
                  'No legs yet. Tap ＋ to add.',
                  style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontStyle: FontStyle.italic),
                ),
              ),
            )
          else
            for (var i = 0; i < legs.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: borderColor),
              InkWell(
                onTap: _saving ? null : () => _editLeg(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                  child: Row(
                    children: [
                      Icon(legs[i].mode.icon, size: 16, color: iconColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(legs[i].mode.label,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: textColor)),
                            if (legs[i].line != null &&
                                legs[i].line!.isNotEmpty)
                              Text(legs[i].line!,
                                  style: const TextStyle(
                                      fontSize: 11, color: iconColor)),
                          ],
                        ),
                      ),
                      if (fmtMin(legs[i].durationMin).isNotEmpty) ...[
                        Text(fmtMin(legs[i].durationMin),
                            style: const TextStyle(
                                fontSize: 12, color: textColor)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('·',
                              style: TextStyle(
                                  fontSize: 12, color: textColor)),
                        ),
                      ],
                      Text(fmtCost(legs[i].cost, legs[i].isFree),
                          style: const TextStyle(
                              fontSize: 12, color: textColor)),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded,
                          size: 14, color: iconColor),
                    ],
                  ),
                ),
              ),
            ],

          // ── Add leg ────────────────────────────────────────────────────────
          const Divider(height: 1, color: borderColor),
          InkWell(
            onTap: _saving ? null : _addLeg,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 14, color: iconColor),
                  SizedBox(width: 6),
                  Text('Add leg',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor)),
                ],
              ),
            ),
          ),

          // ── Total row (multi-leg) ──────────────────────────────────────────
          if (multiLeg) ...[
            const Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.summarize_rounded,
                      size: 12, color: iconColor),
                  const SizedBox(width: 5),
                  const Text('Total',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: iconColor)),
                  const Spacer(),
                  if (totalDur.isNotEmpty) ...[
                    Text(totalDur,
                        style: const TextStyle(
                            fontSize: 10, color: iconColor)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('·',
                          style: TextStyle(fontSize: 10, color: iconColor)),
                    ),
                  ],
                  Text(totalCost,
                      style:
                          const TextStyle(fontSize: 10, color: iconColor)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Compact amber container shown in read mode between two stops.
// Shows every leg as its own row; total row appears when legs ≥ 2.
class _TransitRow extends StatelessWidget {
  final TransitSegment segment;
  final String currency;

  const _TransitRow({required this.segment, required this.currency});

  static const _bgColor = Color(0xFFFFF8EC);
  static const _borderColor = Color(0xFFF0E2C2);
  static const _iconColor = Color(0xFFA06D1F);
  static const _textColor = Color(0xFF8A5A18);

  String _fmtCost(double cost, bool isFree) {
    if (isFree || cost <= 0) return 'Free';
    return '${cost.toStringAsFixed(0)} $currency';
  }

  String _fmtMin(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  String _totalCost() {
    if (segment.totalCost <= 0) return 'Free';
    return '${segment.totalCost.toStringAsFixed(0)} $currency';
  }

  String _totalDuration() => _fmtMin(segment.totalDurationMin);

  @override
  Widget build(BuildContext context) {
    final legs = segment.legs;
    final multiLeg = legs.length > 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(28, 6, 28, 6),
      decoration: BoxDecoration(
        color: _bgColor,
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── One row per leg ──────────────────────────────────────────────
          for (var i = 0; i < legs.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: _borderColor, indent: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(legs[i].mode.icon, size: 16, color: _iconColor),
                  const SizedBox(width: 8),
                  Text(
                    legs[i].mode.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                  // line / direction if present
                  if (legs[i].line != null && legs[i].line!.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      legs[i].line!,
                      style: const TextStyle(fontSize: 12, color: _textColor),
                    ),
                  ],
                  const Spacer(),
                  // per-leg duration
                  if (_fmtMin(legs[i].durationMin).isNotEmpty) ...[
                    Text(
                      _fmtMin(legs[i].durationMin),
                      style: const TextStyle(fontSize: 12, color: _textColor),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·',
                          style: TextStyle(fontSize: 12, color: _textColor)),
                    ),
                  ],
                  // per-leg cost
                  Text(
                    _fmtCost(legs[i].cost, legs[i].isFree),
                    style: const TextStyle(fontSize: 12, color: _textColor),
                  ),
                ],
              ),
            ),
          ],

          // ── Total row (multi-leg only) ────────────────────────────────────
          if (multiLeg) ...[
            const Divider(height: 1, color: _borderColor),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.summarize_rounded,
                      size: 13, color: _iconColor),
                  const SizedBox(width: 6),
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _iconColor,
                    ),
                  ),
                  const Spacer(),
                  if (_totalDuration().isNotEmpty) ...[
                    Text(
                      _totalDuration(),
                      style: const TextStyle(
                          fontSize: 11, color: _iconColor),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·',
                          style: TextStyle(
                              fontSize: 11, color: _iconColor)),
                    ),
                  ],
                  Text(
                    _totalCost(),
                    style: const TextStyle(
                        fontSize: 11, color: _iconColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
