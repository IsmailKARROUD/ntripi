// features/reports/presentation/report_content_sheet.dart
//
// The single reporting surface for every kind of user content: itineraries,
// stops, reviews and profiles. Viewer picks one reason and optionally adds
// details; the report is POSTed to /reports.
//
// One sheet for all of them on purpose — a report action missing from any UGC
// surface is an app-store rejection risk, and four near-identical sheets would
// drift apart the first time the category list changed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/reports/data/report_repository.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

String _reasonLabel(String reason, AppLocalizations l10n) {
  return switch (reason) {
    'spam' => l10n.reportReasonSpam,
    'harassment' => l10n.reportReasonHarassment,
    'hate_speech' => l10n.reportReasonHateSpeech,
    'sexual_content' => l10n.reportReasonSexualContent,
    'violence_threat' => l10n.reportReasonViolenceThreat,
    'csam' => l10n.reportReasonCsam,
    _ => l10n.reportReasonOther,
  };
}

// Names what is being reported. Stops and annotations are wire-reported as
// their parent itinerary, so the title is the only place the viewer sees that
// their report is about the fragment they actually tapped.
String _targetTitle(ReportTarget target, AppLocalizations l10n) {
  if (target.isAnnotation) return l10n.reportAnnotation;
  if (target.isStop) return l10n.reportStop;
  return switch (target.kind) {
    ReportTargetKind.rating => l10n.reportReview,
    ReportTargetKind.user => l10n.reportUser,
    ReportTargetKind.itinerary => l10n.reportItineraryTitle,
  };
}

/// Opens the report bottom sheet and returns when the user submits or dismisses.
Future<void> showReportContentSheet(
  BuildContext context,
  WidgetRef ref,
  ReportTarget target,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportContentSheet(target: target, parentRef: ref),
  );
}

// ---------------------------------------------------------------------------

class _ReportContentSheet extends StatefulWidget {
  final ReportTarget target;
  final WidgetRef parentRef;

  const _ReportContentSheet({required this.target, required this.parentRef});

  @override
  State<_ReportContentSheet> createState() => _ReportContentSheetState();
}

class _ReportContentSheetState extends State<_ReportContentSheet> {
  String? _reason;
  final _notesController = TextEditingController();
  bool _saving = false;
  // Shown inline rather than via a snackbar: the sheet stays open on failure, so
  // a root-messenger snackbar renders behind the modal barrier and is never seen.
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    final l10n = AppLocalizations.of(context)!;
    // Capture the messenger before the async gap — this context is disposed
    // once the sheet pops.
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.parentRef.read(reportRepositoryProvider).report(
            target: widget.target,
            reason: _reason!,
            notes: _notesController.text,
          );
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.reportThanks)));
    } on Exception catch (e) {
      if (!mounted) return;
      // Keep the sheet open with the reason and notes intact so Submit retries.
      setState(() {
        _saving = false;
        _error = extractErrorMessage(e, l10n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final canSubmit = _reason != null && !_saving;

    return PopScope(
      canPop: !_saving,
      child: SavingOverlay(
        saving: _saving,
        tint: nt.surface,
        loaderSize: 40,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sheet drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: nt.text3.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
                child: Text(
                  _targetTitle(widget.target, l10n),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: nt.bark,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              // ── Reason list (single choice) ──────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                decoration: BoxDecoration(
                  color: nt.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: nt.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < kReportReasons.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, indent: 16, endIndent: 16, color: nt.border),
                      _ReasonRow(
                        label: _reasonLabel(kReportReasons[i], l10n),
                        selected: _reason == kReportReasons[i],
                        onTap: _saving
                            ? null
                            : () => setState(() => _reason = kReportReasons[i]),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Notes (optional) ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TextField(
                  controller: _notesController,
                  enabled: !_saving,
                  maxLength: 2000,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: l10n.reportNotesHint,
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
              ),

              // ── Failure message ──────────────────────────────────────────
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
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
                ),

              const SizedBox(height: 8),

              // ── Action buttons ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
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
                              : Text(l10n.reportSubmit),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Single tappable reason row with a trailing radio glyph.
class _ReasonRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonRow({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
