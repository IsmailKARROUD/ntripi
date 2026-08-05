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
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_editor.dart';
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

  // Leg mutations are shared with the stop detail screen's transit rows.
  LegEditor get _legs => LegEditor(
        ref: ref,
        itineraryId: widget.itineraryId,
        segment: widget.segment,
        onSavingChanged: (saving) {
          if (mounted) setState(() => _saving = saving);
        },
      );

  Future<void> _addLeg() => _legs.addLeg(context);

  Future<void> _editLeg(int index) => _legs.editLeg(context, index);

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
