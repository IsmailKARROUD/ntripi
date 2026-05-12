// widgets/annotation_form_dialog.dart — Reusable dialog for add and edit.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
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
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LabelWithHelp(
              label: 'Type',
              helpTitle: 'Annotation type',
              helpMessage:
                  "Advice: a helpful tip. Caution: be careful. Avoid: don't go. Info: a neutral note.",
            ),
            const SizedBox(height: 8),
            SegmentedButton<AnnotationType>(
              segments: const [
                ButtonSegment(
                  value: AnnotationType.advice,
                  label: Text('Advice'),
                  icon: Icon(Icons.lightbulb_outline, size: 16),
                ),
                ButtonSegment(
                  value: AnnotationType.caution,
                  label: Text('Caution'),
                  icon: Icon(Icons.warning_amber_outlined, size: 16),
                ),
                ButtonSegment(
                  value: AnnotationType.avoid,
                  label: Text('Avoid'),
                  icon: Icon(Icons.block, size: 16),
                ),
                ButtonSegment(
                  value: AnnotationType.info,
                  label: Text('Info'),
                  icon: Icon(Icons.info_outline, size: 16),
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
              decoration: const InputDecoration(
                label: LabelWithHelp(
                  label: 'Content *',
                  helpTitle: 'Content',
                  helpMessage:
                      'Describe your advice, caution, warning, or note in one or two sentences.',
                ),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Content is required'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
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
  return showDialog<AnnotationFormResult>(
    context: context,
    builder: (_) => AnnotationFormDialog(
      title: isEdit ? 'Edit annotation' : 'Add annotation',
      submitLabel: isEdit ? 'Save' : 'Add',
      initialContent: initialContent ?? '',
      initialType: initialType ?? AnnotationType.advice,
    ),
  );
}
