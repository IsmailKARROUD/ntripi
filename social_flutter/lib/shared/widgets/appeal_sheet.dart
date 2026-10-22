// shared/widgets/appeal_sheet.dart — the one appeal compose surface.
//
// Lives here rather than in account_status_screen because an appeal can now be
// filed from two places: the violations list, and the hidden banner rendered in
// context on the content itself. Both post the same polymorphic
// {target_type, target_id, reason} body.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/profile/domain/violation.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/keyboard_avoidance.dart';

/// Opens the appeal composer for [targetType]/[targetId].
///
/// Returns true when the server accepted the appeal. Hands the violations list
/// it answered with to Account status, and confirms with a snackbar on
/// success, so callers only await it.
Future<bool> showAppealSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  // Captured before the await: the caller may be gone when the sheet closes.
  final container = ProviderScope.containerOf(context, listen: false);

  final violations = await showModalBottomSheet<List<Violation>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // Scrolls, so a short window or large text can no longer overflow it.
    builder: (_) => KeyboardSafeSheetBody(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: AppealSheet(targetType: targetType, targetId: targetId),
    ),
  );

  if (violations == null) return false;
  // The list as it now stands, adopted where Account status is open — reading
  // the provider anywhere else would build it, which is a GET.
  if (container.exists(myViolationsProvider)) {
    container.read(myViolationsProvider.notifier).adopt(violations);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.appealSubmitted)),
    );
  }
  return true;
}

/// Bottom sheet holding the appeal explanation. Pops the violations list the
/// server answered with once it accepts the appeal.
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
      final violations = await ref.read(profileRepositoryProvider).submitAppeal(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
          );
      if (mounted) Navigator.of(context).pop(violations);
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
        // The whole box, counter and error rise above the keyboard together.
        RevealTogether(
          child: TextField(
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
