// features/bug_report/presentation/bug_report_sheet.dart
//
// The compose half of the shake-to-report flow: the `feedback` package supplies
// the screenshot and the draw-over layer, this supplies everything below it.
//
// Deliberately not the package's stock StringFeedback sheet — that is a grey
// box with one text field, and it would be the only surface in the app that
// does not look like Ntripi. The layout mirrors report_content_sheet.dart, the
// house style for "pick one reason, add detail, submit".
//
// This renders inside BetterFeedback, which is mounted in MaterialApp.builder,
// so context.nt and AppLocalizations.of(context) both resolve normally.

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/bug_report/domain/bug_report_diagnostics.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

String _categoryLabel(String category, AppLocalizations l10n) {
  return switch (category) {
    'crash' => l10n.bugReportCategoryCrash,
    'visual' => l10n.bugReportCategoryVisual,
    'data' => l10n.bugReportCategoryData,
    'slow' => l10n.bugReportCategorySlow,
    _ => l10n.bugReportCategoryOther,
  };
}

class BugReportSheet extends StatefulWidget {
  /// Handed to us by BetterFeedback; resolves once the report has been sent.
  final OnSubmit onSubmit;

  /// Non-null while the feedback sheet is draggable — attaching it to our
  /// scroll view is what lets a drag on the content expand the sheet.
  final ScrollController? scrollController;

  const BugReportSheet({
    super.key,
    required this.onSubmit,
    required this.scrollController,
  });

  @override
  State<BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<BugReportSheet> {
  final _messageController = TextEditingController();
  String? _category;
  bool _saving = false;
  // Shown inline, not via a snackbar: the feedback UI covers the whole screen,
  // so a root-messenger snackbar would render behind it and never be seen.
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The entry point owns the network call — it is the only party holding
      // the screenshot bytes. It rethrows so the sheet can stay open on failure.
      await widget.onSubmit(message, extras: {'category': _category});
    } on Object catch (e) {
      if (!mounted) return;
      // Keep the sheet open with the message and category intact so Send retries.
      setState(() {
        _saving = false;
        _error = extractErrorMessage(e, AppLocalizations.of(context)!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final canSubmit = !_saving && _messageController.text.trim().isNotEmpty;

    return Stack(
      children: [
        ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(
            16,
            // Clears the package's drag handle, which is stacked over us.
            widget.scrollController != null ? 24 : 16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          children: [
            Text(
              l10n.bugReportTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: nt.bark,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),

            // ── Category (optional single choice) ──────────────────────────
            Container(
              decoration: BoxDecoration(
                color: nt.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: nt.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < kBugCategories.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: nt.border,
                      ),
                    _CategoryRow(
                      label: _categoryLabel(kBugCategories[i], l10n),
                      selected: _category == kBugCategories[i],
                      onTap: _saving
                          ? null
                          : () =>
                              setState(() => _category = kBugCategories[i]),
                    ),
                  ],
                ],
              ),
            ),

            // ── What happened ──────────────────────────────────────────────
            const SizedBox(height: 14),
            TextField(
              controller: _messageController,
              enabled: !_saving,
              maxLength: 2000,
              maxLines: 4,
              minLines: 2,
              // Rebuilds so Send enables the moment there is something to send.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.bugReportHint,
                filled: true,
                fillColor: nt.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: nt.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: nt.border),
                ),
              ),
            ),

            // What we attach is stated up front — the user cannot redact the
            // screenshot, so they must at least know it is going.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: nt.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.bugReportAttachmentNotice,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: nt.text2,
                    ),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: nt.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 13, color: nt.danger),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => BetterFeedback.of(context).hide(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OfflineGate(
                    builder: (online) => FilledButton(
                      onPressed: (canSubmit && online) ? _submit : null,
                      child: _saving
                          ? const NTripiRingLoader(size: 18)
                          : Text(l10n.bugReportSubmit),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (widget.scrollController != null) const FeedbackSheetDragHandle(),
      ],
    );
  }
}

// Single tappable category row with a trailing radio glyph.
class _CategoryRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: nt.bark,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? nt.forest : nt.text3,
            ),
          ],
        ),
      ),
    );
  }
}
