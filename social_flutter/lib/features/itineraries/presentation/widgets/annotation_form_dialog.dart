// widgets/annotation_form_dialog.dart — Reusable dialog for add and edit.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/moderation_hint.dart';

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
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title,
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: nt.bark)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 2×2 type card grid ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.annotationTypeLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: nt.text2,
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
                final active = _type == t;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: active ? t.bg(nt) : nt.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? t.fg(nt) : nt.border,
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
                                ? t.fg(nt).withValues(alpha: 0.2)
                                : t.bg(nt),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(t.icon, size: 14, color: t.fg(nt)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.label(l10n),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.fg(nt),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.messageLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: nt.text2,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ModerationHint(
              controller: _contentController,
              child: TextFormField(
                controller: _contentController,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.annotationContentLabel,
                  fillColor: nt.surface,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: nt.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: nt.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: nt.forest, width: 1.5),
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.annotationContentRequired
                    : null,
              ),
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
