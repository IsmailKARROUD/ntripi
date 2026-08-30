// shared/widgets/appeal_sheet.dart — the one appeal compose surface.
//
// Lives here rather than in account_status_screen because an appeal can now be
// filed from two places: the violations list, and the hidden banner rendered in
// context on the content itself. Both post the same polymorphic
// {target_type, target_id, reason} body.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Opens the appeal composer for [targetType]/[targetId].
///
/// Returns true when the server accepted the appeal. Refreshes the violations
/// feed and confirms with a snackbar on success, so callers only await it.
Future<bool> showAppealSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final nt = context.nt;

  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: nt.sand,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
      ),
      child: AppealSheet(targetType: targetType, targetId: targetId),
    ),
  );

  if (submitted == true) {
    ref.invalidate(myViolationsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.appealSubmitted)),
      );
    }
  }
  return submitted == true;
}

/// Bottom sheet holding the appeal explanation. Pops `true` once the server
/// accepts the appeal.
class AppealSheet extends ConsumerStatefulWidget {
  final String targetType;
  final String targetId;

  const AppealSheet({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  ConsumerState<AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends ConsumerState<AppealSheet> {
  // Owned here, not by the caller: disposing it as soon as showModalBottomSheet
  // returns kills the controller while the sheet's exit animation is still
  // building the TextField ("used after being disposed").
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = l10n.appealReasonRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).submitAppeal(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          // appeal_already_pending / appeal_cooldown arrive as coded errors —
          // extractErrorMessage localizes them via api_error_codes.
          _error = extractErrorMessage(e, l10n);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.appealFormTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: nt.bark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.appealFormMessage,
          style: TextStyle(fontSize: 13, color: nt.text2),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('appealReasonField'),
          controller: _controller,
          maxLines: 5,
          maxLength: 2000,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: l10n.appealReasonLabel,
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('appealSubmitButton'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.appealSubmit),
          ),
        ),
      ],
    );
  }
}
