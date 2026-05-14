// widgets/annotation_form_dialog.dart — Reusable dialog for add and edit.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Result returned when the user confirms the dialog.
typedef AnnotationFormResult = ({String content, AnnotationType type});

/// Dialog used for both creating and editing annotations.
/// Pass [initialContent] and [initialType] to pre-fill in edit mode.
class AnnotationFormDialog extends StatefulWidget {
  final String title;
  final String submitLabel;
  final String initialContent;
  final AnnotationType initialType;

  const AnnotationFormDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    this.initialContent = '',
    this.initialType = AnnotationType.advice,
  });

  @override
  State<AnnotationFormDialog> createState() => _AnnotationFormDialogState();
}

class _AnnotationFormDialogState extends State<AnnotationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late AnnotationType _type;
  late final TextEditingController _contentController;

  // Design tokens for each annotation type.
  static const _palette = {
    AnnotationType.advice: (
      bg: Color(0xFFE0EBE4),
      fg: kForest,
      icon: Icons.lightbulb_rounded,
      label: 'Tip',
      desc: 'Something useful or pro-tip.',
    ),
    AnnotationType.caution: (
      bg: Color(0xFFFFE3CC),
      fg: Color(0xFFA05D1F),
      icon: Icons.warning_rounded,
      label: 'Caution',
      desc: 'Pay attention — surprises possible.',
    ),
    AnnotationType.avoid: (
      bg: Color(0xFFFFD6D2),
      fg: Color(0xFFA02828),
      icon: Icons.block_rounded,
      label: 'Avoid',
      desc: 'Don\'t do this. Save your time.',
    ),
    AnnotationType.info: (
      bg: Color(0xFFDCEAF6),
      fg: Color(0xFF3B6EA5),
      icon: Icons.info_rounded,
      label: 'Info',
      desc: 'A neutral fact worth knowing.',
    ),
  };

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: kSand,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: kBark)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 2×2 type card grid ─────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'TYPE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kText2,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: AnnotationType.values.map((t) {
                final p = _palette[t]!;
                final active = _type == t;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: active ? p.bg : kSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? p.fg : kBorder,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: active
                                ? p.fg.withValues(alpha: 0.2)
                                : p.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(p.icon, size: 14, color: p.fg),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // ── Content field ──────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'MESSAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kText2,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            TextFormField(
              controller: _contentController,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.annotationContentLabel,
                fillColor: kSurface,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kForest, width: 1.5),
                ),
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.annotationContentRequired
                  : null,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop<AnnotationFormResult>(
              context,
              (content: _contentController.text.trim(), type: _type),
            );
          },
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

/// Convenience function to show the dialog and await the result.
Future<AnnotationFormResult?> showAnnotationFormDialog(
  BuildContext context, {
  String? initialContent,
  AnnotationType? initialType,
  required bool isEdit,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<AnnotationFormResult>(
    context: context,
    builder: (_) => AnnotationFormDialog(
      title: isEdit ? l10n.editAnnotationTitle : l10n.addAnnotationDialogTitle,
      submitLabel: isEdit ? l10n.saveButton : l10n.addButton,
      initialContent: initialContent ?? '',
      initialType: initialType ?? AnnotationType.advice,
    ),
  );
}
