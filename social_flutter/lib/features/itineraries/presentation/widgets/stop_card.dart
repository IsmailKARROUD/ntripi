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
              decoration: const BoxDecoration(
                color: kMist,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$trackIndex',
                style: const TextStyle(
                  color: kForest,
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kBark,
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
                          const Icon(Icons.location_on_rounded,
                              size: 12, color: kText3),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              stop.placeAddress!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kText2,
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
                          const Icon(Icons.payments_rounded,
                              size: 12, color: kText3),
                          const SizedBox(width: 2),
                          Text(
                            formatMoney(stop.cost, currency),
                            style: const TextStyle(
                              fontSize: 12,
                              color: kText2,
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
                Icon(Icons.notes_rounded, size: 14, color: kText3),
                const SizedBox(width: 4),
                Text(
                  'Notes',
                  style: const TextStyle(
                    fontSize: 12,
                    color: kText2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: kText3,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
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

  static const _style = TextStyle(fontSize: 13, height: 1.4, color: kText2);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.notes, style: _style),
          maxLines: 2,
          textDirection: TextDirection.ltr,
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
                style: _style,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (overflows || _expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? 'view less' : '... view more',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kForest,
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
                color: kEditBlueTint,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kEditBlue.withValues(alpha: 0.13)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 13, color: kEditBlue),
                  SizedBox(width: 3),
                  Text(
                    'Add note',
                    style: TextStyle(fontSize: 12, color: kEditBlue),
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

  static const _colors = {
    AnnotationType.advice: (bg: Color(0xFFE0EBE4), fg: kForest),
    AnnotationType.caution: (bg: Color(0xFFFFE3CC), fg: Color(0xFFA05D1F)),
    AnnotationType.avoid: (bg: Color(0xFFFFD6D2), fg: Color(0xFFA02828)),
    AnnotationType.info: (bg: Color(0xFFDCEAF6), fg: Color(0xFF3B6EA5)),
  };

  static const _icons = {
    AnnotationType.advice: Icons.lightbulb_rounded,
    AnnotationType.caution: Icons.warning_rounded,
    AnnotationType.avoid: Icons.block_rounded,
    AnnotationType.info: Icons.info_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: annotations.map((a) {
        final c = _colors[a.type];
        final icon = _icons[a.type] ?? Icons.info_rounded;
        if (c == null) return const SizedBox.shrink();
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: c.bg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 11, color: c.fg),
        );
      }).toList(),
    );
  }
}
