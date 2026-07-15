// widgets/stop_card.dart — Single stop row in the itinerary detail list.
//
// Renders as a plain padded row (no Card border) because it always lives
// inside a parent SectionCard. The visual split between read and edit mode:
//   read  — number circle · name/address · inline notes · anno mini-dots
//   edit  — same but with an edit IconButton on the right and full annotation
//            chips (with add-note affordance) instead of dots

import 'package:flutter/material.dart';
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/edit_pencil_button.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class StopCard extends StatelessWidget {
  final Stop stop;
  final String currency;

  /// 1-based track index shown on the number badge. Required.
  final int trackIndex;

  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onAddAnnotation;
  final void Function(Annotation)? onEditAnnotation;
  final void Function(Annotation)? onDeleteAnnotation;

  const StopCard({
    super.key,
    required this.stop,
    required this.currency,
    required this.trackIndex,
    this.onTap,
    this.onEdit,
    this.onAddAnnotation,
    this.onEditAnnotation,
    this.onDeleteAnnotation,
  });

  bool get _editMode => onEdit != null;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final hasNotes = stop.notes != null && stop.notes!.trim().isNotEmpty;
    final hasAnnotations = stop.annotations.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Number badge ─────────────────────────────────────────────────
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: nt.mist,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$trackIndex',
                style: TextStyle(
                  color: nt.forest,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Main content ─────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Place name
                  Text(
                    stop.placeName ?? 'Stop $trackIndex',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: nt.bark,
                      letterSpacing: -0.1,
                    ),
                  ),

                  // Address
                  if (stop.placeAddress != null && stop.placeAddress!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 12, color: nt.text3),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              stop.placeAddress!,
                              style: TextStyle(
                                fontSize: 12,
                                color: nt.text2,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Price — only when the stop is actually paid; free and
                  // unset-cost (cost==0, not free) stops show nothing.
                  if (!stop.isFree && stop.cost > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.payments_rounded,
                              size: 12, color: nt.text3),
                          const SizedBox(width: 2),
                          Text(
                            formatMoney(stop.cost, currency),
                            style: TextStyle(
                              fontSize: 12,
                              color: nt.text2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Notes — always visible in read mode; collapsible in edit
                  if (hasNotes)
                    _editMode
                        ? _EditNotesSection(notes: stop.notes!)
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _ReadNotesSection(notes: stop.notes!),
                          ),

                  // Annotations
                  if (hasAnnotations || (_editMode && onAddAnnotation != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _editMode
                          ? _AnnotationChipsRow(
                              annotations: stop.annotations,
                              onAdd: onAddAnnotation,
                              onEdit: onEditAnnotation,
                              onDelete: onDeleteAnnotation,
                            )
                          : _AnnoMiniRow(annotations: stop.annotations),
                    ),
                ],
              ),
            ),

            // ── Edit button (edit mode only) ──────────────────────────────────
            if (_editMode && onEdit != null) ...[
              const SizedBox(width: 4),
              EditPencilButton(onTap: onEdit, iconSize: 16),
            ],
          ],
        ),
      ),
    );
  }
}

// Collapsible notes section used only in edit mode.
class _EditNotesSection extends StatefulWidget {
  final String notes;
  const _EditNotesSection({required this.notes});

  @override
  State<_EditNotesSection> createState() => _EditNotesSectionState();
}

class _EditNotesSectionState extends State<_EditNotesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notes_rounded, size: 14, color: nt.text3),
                const SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context)!.notesLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: nt.text2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: nt.text3,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: AlignmentDirectional.topStart,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InertMarkdownBody(data: widget.notes),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// 2-line preview with "view more" toggle (read mode).
class _ReadNotesSection extends StatefulWidget {
  final String notes;
  const _ReadNotesSection({required this.notes});

  @override
  State<_ReadNotesSection> createState() => _ReadNotesSectionState();
}

class _ReadNotesSectionState extends State<_ReadNotesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final style = TextStyle(fontSize: 13, height: 1.4, color: nt.text2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.notes, style: style),
          maxLines: 2,
          // must match the rendered Text's direction or the overflow check lies for Arabic notes
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expanded)
              InertMarkdownBody(data: widget.notes)
            else
              Text(
                widget.notes,
                style: style,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (overflows || _expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded
                        ? AppLocalizations.of(context)!.viewLess
                        : AppLocalizations.of(context)!.viewMore,
                    style: TextStyle(
                      fontSize: 12,
                      color: nt.forest,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Full annotation chips with add/edit/delete (edit mode).
class _AnnotationChipsRow extends StatelessWidget {
  final List<Annotation> annotations;
  final VoidCallback? onAdd;
  final void Function(Annotation)? onEdit;
  final void Function(Annotation)? onDelete;

  const _AnnotationChipsRow({
    required this.annotations,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...annotations.map(
          (a) => AnnotationChip(
            annotation: a,
            onEdit: onEdit != null ? () => onEdit!(a) : null,
            onDelete: onDelete != null ? () => onDelete!(a) : null,
          ),
        ),
        if (onAdd != null)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: nt.editBlueTint,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: nt.editBlue.withValues(alpha: 0.13)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 13, color: nt.editBlue),
                  const SizedBox(width: 3),
                  Text(
                    AppLocalizations.of(context)!.addAnnotationButton,
                    style: TextStyle(fontSize: 12, color: nt.editBlue),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// Tiny colored dot per annotation type (read mode).
class _AnnoMiniRow extends StatelessWidget {
  final List<Annotation> annotations;
  const _AnnoMiniRow({required this.annotations});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: annotations.map((a) {
        // colors/icons come from the domain enum — single source of truth
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: a.type.bg(nt),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(a.type.icon, size: 11, color: a.type.fg(nt)),
        );
      }).toList(),
    );
  }
}
