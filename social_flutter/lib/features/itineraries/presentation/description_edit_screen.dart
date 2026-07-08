// presentation/description_edit_screen.dart — dedicated full-screen editor for
// an itinerary's description. Reached by tapping the description row while the
// owner is in edit mode on the detail screen.
//
// Persists via itineraryDetailProvider(id).notifier.updateHeader({'description'})
// which mutates the shared provider state in place, so the detail screen the
// user returns to reflects the new description with no explicit invalidate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class DescriptionEditScreen extends ConsumerStatefulWidget {
  final String itineraryId;

  const DescriptionEditScreen({super.key, required this.itineraryId});

  @override
  ConsumerState<DescriptionEditScreen> createState() =>
      _DescriptionEditScreenState();
}

class _DescriptionEditScreenState extends ConsumerState<DescriptionEditScreen> {
  final TextEditingController _controller = TextEditingController();
  // Baseline used to detect unsaved edits before leaving.
  late final String _initialText;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Provider is already loaded (we arrived here from the detail screen).
    final desc = ref
            .read(itineraryDetailProvider(widget.itineraryId))
            .value
            ?.description ??
        '';
    _initialText = desc;
    _controller.text = desc;
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
    final dirty = _controller.text.trim() != _initialText.trim();
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

  Future<void> _save() async {
    final text = _controller.text.trim();
    setState(() => _saving = true);
    try {
      await ref
          .read(itineraryDetailProvider(widget.itineraryId).notifier)
          .updateHeader({'description': text.isEmpty ? null : text});
      if (!mounted) return;
      context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(extractErrorMessage(
                e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: kSand,
        appBar: AppBar(
          backgroundColor: kSand,
          title: Text(l10n.descriptionLabel),
          actions: [
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: NTripiRingLoader(size: 20),
                  )
                : TextButton(
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
                label: l10n.descriptionLabel,
                helpTitle: l10n.descriptionLabel,
                helpMessage: l10n.descriptionHelp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
