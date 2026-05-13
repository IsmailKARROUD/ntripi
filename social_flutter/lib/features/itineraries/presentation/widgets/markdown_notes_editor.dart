// widgets/markdown_notes_editor.dart — Markdown-source notes editor with
// a small formatting toolbar (B, I, H1, H2, bullet, numbered) and an
// Edit/Preview toggle. In readOnly mode it renders MarkdownBody only.
//
// User-supplied links are intentionally inert: typed link syntax renders
// as plain unstyled text and tapping does nothing. This avoids exposing
// a phishing surface in shared/public itinerary notes.

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:social_flutter/shared/widgets/field_help.dart';

class MarkdownNotesEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool readOnly;
  final String label;
  final String? helpTitle;
  final String? helpMessage;

  const MarkdownNotesEditor({
    super.key,
    required this.controller,
    required this.readOnly,
    this.label = 'Notes',
    this.helpTitle,
    this.helpMessage,
  });

  @override
  State<MarkdownNotesEditor> createState() => _MarkdownNotesEditorState();
}

class _MarkdownNotesEditorState extends State<MarkdownNotesEditor> {
  bool _previewMode = false;

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return _ReadOnlyNotes(text: widget.controller.text, label: widget.label);
    }

    final borderColor = Theme.of(context).dividerColor;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        );
    final hasHelp =
        widget.helpTitle != null && widget.helpMessage != null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: hasHelp
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: labelStyle),
                      const SizedBox(width: 2),
                      FieldHelpIcon(
                        helpTitle: widget.helpTitle!,
                        helpMessage: widget.helpMessage!,
                        size: 16,
                      ),
                    ],
                  )
                : Text(widget.label, style: labelStyle),
          ),
          _Toolbar(
            controller: widget.controller,
            previewMode: _previewMode,
            onTogglePreview: (v) => setState(() => _previewMode = v),
            disabled: _previewMode,
          ),
          const Divider(height: 1),
          if (_previewMode)
            _PreviewBody(text: widget.controller.text)
          else
            TextField(
              controller: widget.controller,
              minLines: 4,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyNotes extends StatelessWidget {
  final String text;
  final String label;
  const _ReadOnlyNotes({required this.text, required this.label});

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        InertMarkdownBody(data: text),
      ],
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final String text;
  const _PreviewBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: text.trim().isEmpty
          ? Text(
              'Nothing to preview yet.',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontStyle: FontStyle.italic,
              ),
            )
          : InertMarkdownBody(data: text),
    );
  }
}

/// Markdown renderer used everywhere notes are displayed.
///
/// Intentional choices:
/// - `md.ExtensionSet.none` — no GFM extensions, no www auto-linking.
/// - No `onTapLink` — taps on link nodes do nothing.
/// - `styleSheet.a` matches body text — typed link syntax is visually
///   indistinguishable from regular text, so users don't perceive
///   user-supplied URLs as clickable.
class InertMarkdownBody extends StatelessWidget {
  final String data;
  const InertMarkdownBody({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = MarkdownStyleSheet.fromTheme(theme);
    final bodyStyle = theme.textTheme.bodyMedium;
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.none,
      styleSheet: base.copyWith(a: bodyStyle),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final bool previewMode;
  final ValueChanged<bool> onTogglePreview;
  final bool disabled;

  const _Toolbar({
    required this.controller,
    required this.previewMode,
    required this.onTogglePreview,
    required this.disabled,
  });

  void _wrap(String marker, {required String placeholder}) {
    final sel = controller.selection;
    final text = controller.text;
    if (!sel.isValid) {
      final insertion = '$marker$placeholder$marker';
      controller.value = TextEditingValue(
        text: text + insertion,
        selection: TextSelection(
          baseOffset: text.length + marker.length,
          extentOffset: text.length + marker.length + placeholder.length,
        ),
      );
      return;
    }
    if (sel.isCollapsed) {
      final insertion = '$marker$placeholder$marker';
      final newText = text.replaceRange(sel.start, sel.end, insertion);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + marker.length,
          extentOffset: sel.start + marker.length + placeholder.length,
        ),
      );
    } else {
      final selected = text.substring(sel.start, sel.end);
      final newText =
          text.replaceRange(sel.start, sel.end, '$marker$selected$marker');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + marker.length,
          extentOffset: sel.start + marker.length + selected.length,
        ),
      );
    }
  }

  void _prefixLines(String prefix) {
    final text = controller.text;
    final sel = controller.selection;
    final hasSel = sel.isValid;

    final start = hasSel ? sel.start : text.length;
    final end = hasSel ? sel.end : text.length;

    final (lineStart, lineEnd) = _lineRange(text, start, end);

    final block = text.substring(lineStart, lineEnd);
    final newBlock =
        block.split('\n').map((line) => '$prefix$line').join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, newBlock);

    final addedTotal = newBlock.length - block.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: end + addedTotal),
    );
  }

  void _prefixOrdered() {
    final text = controller.text;
    final sel = controller.selection;
    final hasSel = sel.isValid;

    final start = hasSel ? sel.start : text.length;
    final end = hasSel ? sel.end : text.length;

    final (lineStart, lineEnd) = _lineRange(text, start, end);

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');
    final newBlock = [
      for (var i = 0; i < lines.length; i++) '${i + 1}. ${lines[i]}',
    ].join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, newBlock);

    final addedTotal = newBlock.length - block.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: end + addedTotal),
    );
  }

  // Returns the (lineStart, lineEnd) byte range of all lines touched by the
  // [start, end] selection. lineStart is 0 when the selection starts at the
  // very beginning of the document — guarded explicitly because
  // String.lastIndexOf throws RangeError on a negative start argument.
  static (int, int) _lineRange(String text, int start, int end) {
    final lineStart =
        start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    var lineEnd = text.indexOf('\n', end);
    if (lineEnd == -1) lineEnd = text.length;
    return (lineStart, lineEnd);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = disabled
        ? Theme.of(context).disabledColor
        : Theme.of(context).iconTheme.color;

    Widget btn({
      required IconData icon,
      required String tooltip,
      required VoidCallback action,
    }) {
      return IconButton(
        icon: Icon(icon, size: 18, color: iconColor),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: disabled ? null : action,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  btn(
                    icon: Icons.format_bold,
                    tooltip: 'Bold',
                    action: () => _wrap('**', placeholder: 'bold'),
                  ),
                  btn(
                    icon: Icons.format_italic,
                    tooltip: 'Italic',
                    action: () => _wrap('*', placeholder: 'italic'),
                  ),
                  btn(
                    icon: Icons.title,
                    tooltip: 'Heading 1',
                    action: () => _prefixLines('# '),
                  ),
                  btn(
                    icon: Icons.text_fields,
                    tooltip: 'Heading 2',
                    action: () => _prefixLines('## '),
                  ),
                  btn(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet list',
                    action: () => _prefixLines('- '),
                  ),
                  btn(
                    icon: Icons.format_list_numbered,
                    tooltip: 'Numbered list',
                    action: _prefixOrdered,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 11),
              ),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Edit')),
              ButtonSegment(value: true, label: Text('Preview')),
            ],
            selected: {previewMode},
            onSelectionChanged: (s) => onTogglePreview(s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

