// widgets/annotation_form_dialog.dart — Reusable dialog for add and edit.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelWithHelp(
              label: l10n.annotationTypeLabel,
              helpTitle: l10n.annotationTypeLabel,
              helpMessage: l10n.annotationTypeHelp,
            ),
            const SizedBox(height: 8),
            SegmentedButton<AnnotationType>(
              segments: [
                ButtonSegment(
                  value: AnnotationType.advice,
                  label: Text(l10n.annotationAdvice),
                  icon: const Icon(Icons.lightbulb_outline, size: 16),
                ),
                ButtonSegment(
                  value: AnnotationType.caution,
                  label: Text(l10n.annotationCaution),
                  icon: const Icon(Icons.warning_amber_outlined, size: 16),
                ),
                ButtonSegment(
                  value: AnnotationType.avoid,
                  label: Text(l10n.annotationAvoid),
                  icon: const Icon(Icons.block, size: 16),
                ),
                ButtonSegment(
                  value: AnnotationType.info,
                  label: Text(l10n.annotationInfo),
                  icon: const Icon(Icons.info_outline, size: 16),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contentController,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.annotationContentLabel,
                suffixIcon: FieldHelpIcon(
                  helpTitle: l10n.annotationContentLabel,
                  helpMessage: l10n.annotationContentHelp,
                ),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.annotationContentRequired
                  : null,
            ),
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
