// shared/widgets/markdown_edit_screen.dart — reusable full-screen markdown text
// editor for a single free-text field (itinerary description, profile bio, …).
//
// It is intentionally provider-agnostic: it pops with the trimmed new value on
// Save (an empty string means the field was cleared) or with null if the user
// backs out. Persistence is the caller's job — push it via editMarkdownField()
// and act on the returned String.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/moderation_hint.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

/// Opens [MarkdownEditScreen] and resolves to the edited text, or null if the
/// user left without saving. An empty string means the field was cleared.
///
/// When [onSave] is provided the editor persists inline: tapping Save runs it
/// while showing a spinner, keeps the screen open (text intact) if it throws,
/// and only pops with the value once it succeeds. When omitted the editor pops
/// immediately on Save and the caller persists the returned value.
Future<String?> editMarkdownField(
  BuildContext context, {
  required String initialText,
  required String title,
  String? helpTitle,
  String? helpMessage,
  Future<void> Function(String value)? onSave,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => MarkdownEditScreen(
        initialText: initialText,
        title: title,
        helpTitle: helpTitle,
        helpMessage: helpMessage,
        onSave: onSave,
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

  /// Optional inline persister — see [editMarkdownField]. Null → pop on Save.
  final Future<void> Function(String value)? onSave;

  const MarkdownEditScreen({
    super.key,
    required this.initialText,
    required this.title,
    this.helpTitle,
    this.helpMessage,
    this.onSave,
  });

  @override
  State<MarkdownEditScreen> createState() => _MarkdownEditScreenState();
}

class _MarkdownEditScreenState extends State<MarkdownEditScreen> {
  late final TextEditingController _controller;
  bool _dirty = false;
  bool _saving = false;

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

  // Save the trimmed value (empty = cleared). With no inline [onSave] we just
  // pop and let the caller persist. With one we run it behind a spinner, staying
  // open on failure so the user's text survives, and pop only once it succeeds.
  Future<void> _save() async {
    final value = _controller.text.trim();
    final onSave = widget.onSave;
    if (onSave == null) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() => _saving = true);
    try {
      await onSave(value);
      if (mounted) Navigator.of(context).pop(value);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      // Block back-out while a save is in flight — the value is being persisted.
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final discard = await _confirmDiscard();
        // Discard → pop with null so the caller keeps the old value.
        if (!discard || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: SavingOverlay(
        saving: _saving,
        child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: nt.surface,
        appBar: AppBar(
          backgroundColor: nt.surface,
          // Hide the back arrow mid-save so the only way out is a finished save.
          automaticallyImplyLeading: !_saving,
          title: Text(widget.title),
          actions: [
            if (_saving)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: nt.forest),
                  ),
                ),
              )
            else
              OfflineGate(
                builder: (online) => TextButton(
                  onPressed: online ? _save : null,
                  child: Text(
                    l10n.save,
                    style: TextStyle(
                      color: online ? nt.forest : nt.text3,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
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
              // Every caller edits prose here (description, bio) — a future
              // title-type field must opt out: place names false-positive.
              child: ModerationHint(
                controller: _controller,
                child: MarkdownNotesEditor(
                  controller: _controller,
                  readOnly: _saving,
                  label: widget.title,
                  helpTitle: widget.helpTitle,
                  helpMessage: widget.helpMessage,
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
