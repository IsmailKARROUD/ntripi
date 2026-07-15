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
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/utils/duration_format.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

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
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
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
          SnackBar(
            content: Text(AppLocalizations.of(context)!.segmentNeedsOneLeg),
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
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final segment = widget.segment;

    // Read mode: compact amber transit row matching the design.
    if (!_isEditable) return _TransitRow(segment: segment, currency: widget.currency);

    // Edit mode: amber editorial container with tappable leg rows.

    String fmtCost(double cost, bool isFree) {
      if (isFree || cost <= 0) return l10n.freeLegLabel;
      return formatMoney(cost, widget.currency);
    }

    String fmtMin(int? m) => formatDuration(m, l10n, fallback: '');

    final legs = segment.legs;
    final multiLeg = legs.length > 1;

    final totalDur = fmtMin(segment.totalDurationMin);
    final totalCost = segment.totalCost <= 0
        ? l10n.freeLegLabel
        : formatMoney(segment.totalCost, widget.currency);

    // Every interactive element below (delete, leg rows, add leg) mutates —
    // one gate at the root blocks them all offline and explains on tap.
    return OfflineGate(
      builder: (_) => Container(
      margin: const EdgeInsets.fromLTRB(28, 6, 28, 6),
      decoration: BoxDecoration(
        color: nt.transitBg,
        border: Border.all(color: nt.transitBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: label + spinner / delete ──────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
            child: Row(
              children: [
                Text(
                  l10n.transitLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: nt.transitIcon,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (_saving)
                  const NTripiRingLoader(size: 14)
                else if (widget.onDelete != null)
                  GestureDetector(
                    onTap: widget.onDelete,
                    child: Icon(Icons.delete_outline_rounded,
                        size: 16, color: nt.ratingRed),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: nt.transitBorder),

          // ── Leg rows (tappable to edit) ────────────────────────────────────
          if (legs.isEmpty)
            InkWell(
              onTap: _saving ? null : _addLeg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Text(
                  l10n.noLegsYetTapAdd,
                  style: TextStyle(
                      fontSize: 12,
                      color: nt.transitText,
                      fontStyle: FontStyle.italic),
                ),
              ),
            )
          else
            for (var i = 0; i < legs.length; i++) ...[
              if (i > 0) Divider(height: 1, color: nt.transitBorder),
              InkWell(
                onTap: _saving ? null : () => _editLeg(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                  child: Row(
                    children: [
                      Icon(legs[i].mode.icon, size: 16, color: nt.transitIcon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(legs[i].mode.label(l10n),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: nt.transitText)),
                            if (legs[i].line != null &&
                                legs[i].line!.isNotEmpty)
                              Text(legs[i].line!,
                                  style: TextStyle(
                                      fontSize: 11, color: nt.transitIcon)),
                          ],
                        ),
                      ),
                      if (fmtMin(legs[i].durationMin).isNotEmpty) ...[
                        Text(fmtMin(legs[i].durationMin),
                            style: TextStyle(
                                fontSize: 12, color: nt.transitText)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('·',
                              style: TextStyle(
                                  fontSize: 12, color: nt.transitText)),
                        ),
                      ],
                      Text(fmtCost(legs[i].cost, legs[i].isFree),
                          style: TextStyle(
                              fontSize: 12, color: nt.transitText)),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 14, color: nt.transitIcon),
                    ],
                  ),
                ),
              ),
            ],

          // ── Add leg ────────────────────────────────────────────────────────
          Divider(height: 1, color: nt.transitBorder),
          InkWell(
            onTap: _saving ? null : _addLeg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 14, color: nt.editBlue),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context)!.addLegButton,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: nt.editBlue)),
                ],
              ),
            ),
          ),

          // ── Total row (multi-leg) ──────────────────────────────────────────
          if (multiLeg) ...[
            Divider(height: 1, color: nt.transitBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  Icon(Icons.summarize_rounded,
                      size: 12, color: nt.transitIcon),
                  const SizedBox(width: 5),
                  Text(AppLocalizations.of(context)!.totalLabel,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: nt.transitIcon)),
                  const Spacer(),
                  if (totalDur.isNotEmpty) ...[
                    Text(totalDur,
                        style: TextStyle(
                            fontSize: 10, color: nt.transitIcon)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('·',
                          style: TextStyle(fontSize: 10, color: nt.transitIcon)),
                    ),
                  ],
                  Text(totalCost,
                      style:
                          TextStyle(fontSize: 10, color: nt.transitIcon)),
                ],
              ),
            ),
          ],
        ],
      ),
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

  String _fmtCost(double cost, bool isFree, AppLocalizations l10n) {
    if (isFree || cost <= 0) return l10n.freeLegLabel;
    return formatMoney(cost, currency);
  }

  String _fmtMin(int? minutes, AppLocalizations l10n) =>
      formatDuration(minutes, l10n, fallback: '');

  String _totalCost(AppLocalizations l10n) {
    if (segment.totalCost <= 0) return l10n.freeLegLabel;
    return formatMoney(segment.totalCost, currency);
  }

  String _totalDuration(AppLocalizations l10n) =>
      _fmtMin(segment.totalDurationMin, l10n);

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final legs = segment.legs;
    final multiLeg = legs.length > 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(28, 6, 28, 6),
      decoration: BoxDecoration(
        color: nt.transitBg,
        border: Border.all(color: nt.transitBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── One row per leg ──────────────────────────────────────────────
          for (var i = 0; i < legs.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: nt.transitBorder, indent: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(legs[i].mode.icon, size: 16, color: nt.transitIcon),
                  const SizedBox(width: 8),
                  Text(
                    legs[i].mode.label(l10n),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: nt.transitText,
                    ),
                  ),
                  // line / direction if present
                  if (legs[i].line != null && legs[i].line!.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      legs[i].line!,
                      style: TextStyle(fontSize: 12, color: nt.transitText),
                    ),
                  ],
                  const Spacer(),
                  // per-leg duration
                  if (_fmtMin(legs[i].durationMin, l10n).isNotEmpty) ...[
                    Text(
                      _fmtMin(legs[i].durationMin, l10n),
                      style: TextStyle(fontSize: 12, color: nt.transitText),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·',
                          style: TextStyle(fontSize: 12, color: nt.transitText)),
                    ),
                  ],
                  // per-leg cost
                  Text(
                    _fmtCost(legs[i].cost, legs[i].isFree, l10n),
                    style: TextStyle(fontSize: 12, color: nt.transitText),
                  ),
                ],
              ),
            ),
          ],

          // ── Total row (multi-leg only) ────────────────────────────────────
          if (multiLeg) ...[
            Divider(height: 1, color: nt.transitBorder),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.summarize_rounded,
                      size: 13, color: nt.transitIcon),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.totalLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: nt.transitIcon,
                    ),
                  ),
                  const Spacer(),
                  if (_totalDuration(l10n).isNotEmpty) ...[
                    Text(
                      _totalDuration(l10n),
                      style: TextStyle(
                          fontSize: 11, color: nt.transitIcon),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·',
                          style: TextStyle(
                              fontSize: 11, color: nt.transitIcon)),
                    ),
                  ],
                  Text(
                    _totalCost(l10n),
                    style: TextStyle(
                        fontSize: 11, color: nt.transitIcon),
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
