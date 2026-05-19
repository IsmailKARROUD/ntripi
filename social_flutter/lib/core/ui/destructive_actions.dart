// core/ui/destructive_actions.dart — Three-tier confirmation system.
//
// Tier 1 — showUndoableActionSnackbar  (cheap, reversible actions)
// Tier 2 — confirmDestructiveAction    (simple confirmation dialog)
// Tier 3 — confirmTypedDestructiveAction (type-to-confirm dialog)

import 'package:flutter/material.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Tier 2 — Simple confirmation dialog
// ---------------------------------------------------------------------------

/// Shows an AlertDialog asking the user to confirm a destructive action.
/// Returns true if confirmed, false if cancelled or dismissed.
/// Cancel button has default focus so accidental taps don't destroy data.
Future<bool> confirmDestructiveAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Tier 3 — Type-to-confirm dialog
// ---------------------------------------------------------------------------

/// Shows a dialog where the user must type [requiredText] exactly before
/// the confirm button is enabled. Case-sensitive. Barrier is not dismissible
/// — the user must explicitly tap Cancel.
Future<bool> confirmTypedDestructiveAction({
  required BuildContext context,
  required String title,
  required String message,
  required String requiredText,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  String? hintText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TypedConfirmDialog(
      title: title,
      message: message,
      requiredText: requiredText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      hintText: hintText ?? requiredText,
    ),
  );
  return result ?? false;
}

class _TypedConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String requiredText;
  final String confirmLabel;
  final String cancelLabel;
  final String hintText;

  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.requiredText,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.hintText,
  });

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid => _controller.text.trim() == widget.requiredText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.typeToConfirmInstruction(widget.requiredText),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.hintText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _isValid ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tier 1 — Undoable action snackbar
// ---------------------------------------------------------------------------

/// Hides any current snackbar, then shows "[message] UNDO" for [duration].
/// If the user taps UNDO, [onUndo] is called. Errors in [onUndo] show a
/// second snackbar with error styling.
void showUndoableActionSnackbar({
  required BuildContext context,
  required String message,
  required Future<void> Function() onUndo,
  Duration duration = const Duration(seconds: 5),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      persist: false,
      action: SnackBarAction(
        label: AppLocalizations.of(context)!.undoButton,
        onPressed: () async {
          try {
            await onUndo();
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.couldNotUndo(e.toString())),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          }
        },
      ),
    ),
  );
}
