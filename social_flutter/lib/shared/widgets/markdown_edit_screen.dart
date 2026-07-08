// shared/widgets/markdown_edit_screen.dart — reusable full-screen markdown text
// editor for a single free-text field (itinerary description, profile bio, …).
//
// It is intentionally provider-agnostic: it pops with the trimmed new value on
// Save (an empty string means the field was cleared) or with null if the user
// backs out. Persistence is the caller's job — push it via editMarkdownField()
// and act on the returned String.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Opens [MarkdownEditScreen] and resolves to the edited text, or null if the
/// user left without saving. An empty string means the field was cleared.
Future<String?> editMarkdownField(
  BuildContext context, {
  required String initialText,
  required String title,
  String? helpTitle,
  String? helpMessage,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => MarkdownEditScreen(
        initialText: initialText,
        title: title,
        helpTitle: helpTitle,
        helpMessage: helpMessage,
      ),
    ),
  );
}

class MarkdownEditScreen extends StatefulWidget {
  final String initialText;

  /// Used for both the AppBar title and the editor's field label.
  final String title;
  final String? helpTitle;
  final String? helpMessage;

  const MarkdownEditScreen({
    super.key,
    required this.initialText,
    required this.title,
    this.helpTitle,
    this.helpMessage,
  });

  @override
  State<MarkdownEditScreen> createState() => _MarkdownEditScreenState();
}

class _MarkdownEditScreenState extends State<MarkdownEditScreen> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    // Rebuild only when dirty flips so PopScope.canPop stays accurate.
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final dirty = _controller.text.trim() != widget.initialText.trim();
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context)!;
    return confirmDestructiveAction(
      context: context,
      icon: Icons.logout,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discardButton,
      cancelLabel: l10n.keepEditingButton,
    );
  }

  // Pop with the trimmed value so the caller can persist it (empty = cleared).
  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        // Discard → pop with null so the caller keeps the old value.
        if (!discard || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: kSand,
        appBar: AppBar(
          backgroundColor: kSand,
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(
                l10n.save,
                style: const TextStyle(
                  color: kForest,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              child: MarkdownNotesEditor(
                controller: _controller,
                readOnly: false,
                label: widget.title,
                helpTitle: widget.helpTitle,
                helpMessage: widget.helpMessage,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
