// features/itineraries/presentation/widgets/report_itinerary_sheet.dart
//
// Bottom sheet for reporting an itinerary as inappropriate. Viewer picks one
// reason and optionally adds details; the report is POSTed fire-and-forget to
// /reports (see ItineraryRepository.reportItinerary). Modelled on
// rate_itinerary_dialog.dart (same sheet shape, SavingOverlay, PopScope).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

// Wire values sent to the backend — must match the reason regex in
// app/schemas/report.py. UI-only, so no domain model is needed.
const _kReportReasons = <String>[
  'spam',
  'nsfw',
  'violence',
  'hate_speech',
  'harassment',
  'copyright',
  'other',
];

String _reasonLabel(String reason, AppLocalizations l10n) {
  return switch (reason) {
    'spam' => l10n.reportReasonSpam,
    'nsfw' => l10n.reportReasonNsfw,
    'violence' => l10n.reportReasonViolence,
    'hate_speech' => l10n.reportReasonHateSpeech,
    'harassment' => l10n.reportReasonHarassment,
    'copyright' => l10n.reportReasonCopyright,
    _ => l10n.reportReasonOther,
  };
}

/// Opens the report bottom sheet and returns when the user submits or dismisses.
Future<void> showReportItinerarySheet(
  BuildContext context,
  WidgetRef ref,
  String itineraryId,
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
    builder: (_) => _ReportItinerarySheet(
      itineraryId: itineraryId,
      parentRef: ref,
    ),
  );
}

// ---------------------------------------------------------------------------

class _ReportItinerarySheet extends StatefulWidget {
  final String itineraryId;
  final WidgetRef parentRef;

  const _ReportItinerarySheet({
    required this.itineraryId,
    required this.parentRef,
  });

  @override
  State<_ReportItinerarySheet> createState() => _ReportItinerarySheetState();
}

class _ReportItinerarySheetState extends State<_ReportItinerarySheet> {
  String? _reason;
  final _notesController = TextEditingController();
  bool _saving = false;

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
    setState(() => _saving = true);
    try {
      final notes = _notesController.text.trim();
      await widget.parentRef.read(itineraryRepositoryProvider).reportItinerary(
            itineraryId: widget.itineraryId,
            reason: _reason!,
            notes: notes.isEmpty ? null : notes,
          );
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.reportThanks)));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, l10n))),
      );
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
                  l10n.reportItineraryTitle,
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
                    for (var i = 0; i < _kReportReasons.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, indent: 16, endIndent: 16, color: nt.border),
                      _ReasonRow(
                        label: _reasonLabel(_kReportReasons[i], l10n),
                        selected: _reason == _kReportReasons[i],
                        onTap: _saving
                            ? null
                            : () => setState(() => _reason = _kReportReasons[i]),
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
