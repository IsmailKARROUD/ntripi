// features/itineraries/presentation/widgets/rate_itinerary_dialog.dart
//
// Bottom-sheet dialog matching the "Rate this itinerary" mockup:
//   • Overall stars (required) — shows a thank-you line once tapped
//   • "Want to share more?" section (revealed once Overall is rated) —
//     Safety, Experience, Accessibility, Family-friendly, Crowdedness sub-ratings
//     (Crowdedness uses person glyphs instead of stars; higher = less crowded)
//   • Save / Cancel action buttons

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/my_rating.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/moderation_hint.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

/// Opens the rating bottom sheet and returns when the user saves or dismisses.
Future<void> showRateItineraryDialog(
  BuildContext context,
  WidgetRef ref, {
  required String itineraryId,
  MyRating? current,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // Cap at 70 % of screen height so it never takes over the screen.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RateItinerarySheet(
      itineraryId: itineraryId,
      current: current,
      parentRef: ref,
    ),
  );
}

// ---------------------------------------------------------------------------

class _RateItinerarySheet extends StatefulWidget {
  final String itineraryId;
  final MyRating? current;
  final WidgetRef parentRef;

  const _RateItinerarySheet({
    required this.itineraryId,
    required this.current,
    required this.parentRef,
  });

  @override
  State<_RateItinerarySheet> createState() => _RateItinerarySheetState();
}

class _RateItinerarySheetState extends State<_RateItinerarySheet> {
  late int? _overall;
  late int? _safety;
  late int? _experience;
  late int? _accessibility;
  late int? _familyFriendly;
  late int? _crowdedness;
  final _noteController = TextEditingController();

  bool _saving = false;
  // Shown inline rather than via a snackbar: the sheet stays open on failure, so
  // a root-messenger snackbar renders behind the modal barrier and is never seen.
  String? _error;

  @override
  void initState() {
    super.initState();
    _overall = widget.current?.stars;
    _safety = widget.current?.safetyStars;
    _experience = widget.current?.experienceStars;
    _accessibility = widget.current?.accessibilityStars;
    _familyFriendly = widget.current?.familyFriendlyStars;
    _crowdedness = widget.current?.crowdednessStars;
    _noteController.text = widget.current?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _deleteRating() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.removeRatingTitle,
      message: l10n.removeRatingMessage,
      confirmLabel: l10n.removeButton,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.parentRef
          .read(myRatingProvider(widget.itineraryId).notifier)
          .deleteRating();
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      // Keep the sheet open with every score intact so the action retries.
      setState(() {
        _saving = false;
        _error = extractErrorMessage(e, AppLocalizations.of(context)!);
      });
    }
  }

  Future<void> _save() async {
    if (_overall == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final trimmedNote = _noteController.text.trim();
      await widget.parentRef
          .read(myRatingProvider(widget.itineraryId).notifier)
          .submitRating(MyRating(
            stars: _overall!,
            safetyStars: _safety,
            experienceStars: _experience,
            accessibilityStars: _accessibility,
            familyFriendlyStars: _familyFriendly,
            crowdednessStars: _crowdedness,
            note: trimmedNote.isEmpty ? null : trimmedNote,
          ));
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      // Keep the sheet open with every score intact so Save retries.
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
    final canSave = _overall != null && !_saving;

    // PopScope blocks back-button and barrier-tap dismissal mid-save; the
    // overlay blocks in-sheet taps.
    return PopScope(
      canPop: !_saving,
      child: SavingOverlay(
        saving: _saving,
        loaderSize: 40,
        child: SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
            child: Text(
              l10n.rateItineraryTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: nt.bark,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Text(
              l10n.rateOverallFirstHint,
              style: TextStyle(fontSize: 12, color: nt.text2),
            ),
          ),

          // ── Overall rating (required) ────────────────────────────────────
          SectionCard(
            clipBehavior: Clip.antiAlias,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RatingSliderRow(
                icon: Icons.star_rounded,
                label: l10n.overallRatingLabel,
                isRequired: true,
                value: _overall,
                onChanged: (v) => setState(() => _overall = v),
              ),
            ],
          ),

          // ── Your review (optional) ────────────────────────────────────────
          SectionLabel(label: l10n.yourImpressionLabel),
          SectionCard(
            clipBehavior: Clip.antiAlias,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                // Advisory only — the hint can never disable Submit.
                child: ModerationHint(
                  controller: _noteController,
                  child: MarkdownNotesEditor(
                    controller: _noteController,
                    readOnly: false,
                    label: l10n.yourImpressionLabel,
                    helpTitle: l10n.yourImpressionLabel,
                    helpMessage: l10n.yourImpressionHelp,
                  ),
                ),
              ),
            ],
          ),

          // ── Extra dimensions — revealed only after Overall is rated ──────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _overall == null
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(label: l10n.wantToShareMore),
                      SectionCard(
                        clipBehavior: Clip.antiAlias,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RatingSliderRow(
                            icon: Icons.shield_outlined,
                            label: l10n.safetyLabel,
                            value: _safety,
                            onChanged: (v) => setState(() => _safety = v),
                          ),
                          const FieldDivider(),
                          _RatingSliderRow(
                            icon: Icons.emoji_emotions_outlined,
                            label: l10n.experienceLabel,
                            value: _experience,
                            onChanged: (v) => setState(() => _experience = v),
                          ),
                          const FieldDivider(),
                          _RatingSliderRow(
                            icon: Icons.accessible_outlined,
                            label: l10n.accessibilityLabel,
                            value: _accessibility,
                            onChanged: (v) =>
                                setState(() => _accessibility = v),
                          ),
                          const FieldDivider(),
                          _RatingSliderRow(
                            icon: Icons.family_restroom_outlined,
                            label: l10n.familyFriendlyLabel,
                            value: _familyFriendly,
                            onChanged: (v) =>
                                setState(() => _familyFriendly = v),
                          ),
                          const FieldDivider(),
                          _RatingSliderRow(
                            icon: Icons.groups_outlined,
                            label: l10n.crowdednessLabel,
                            // People glyphs (not stars); inverted so filled =
                            // crowd present (red), empty = uncrowded (green).
                            filledIcon: Icons.person,
                            emptyIcon: Icons.person_outline,
                            inverted: true,
                            value: _crowdedness,
                            onChanged: (v) =>
                                setState(() => _crowdedness = v),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // ── Failure message ───────────────────────────────────────────────
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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

          const SizedBox(height: 20),

          // ── Action buttons ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              children: [
                if (widget.current != null) ...[
                  OfflineGate(
                    builder: (online) => IconButton(
                      icon: Icon(Icons.delete_outline, color: nt.danger),
                      tooltip: l10n.removeMyRatingTooltip,
                      onPressed: (_saving || !online) ? null : _deleteRating,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
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
                      onPressed: (canSave && online) ? _save : null,
                      child: _saving
                          ? const NTripiRingLoader(size: 18)
                          : Text(l10n.saveButton),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dimension row — icon + label on top, large stars + score below
// ---------------------------------------------------------------------------

class _RatingSliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isRequired;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// Rating glyphs — default stars, overridden to person icons for crowdedness.
  final IconData filledIcon;
  final IconData emptyIcon;

  /// Inverted (Uncrowded): fill grows from the right and every glyph is tinted
  /// by the value, so filled people read as "crowd present" (red = crowded).
  final bool inverted;

  const _RatingSliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.isRequired = false,
    this.filledIcon = Icons.star_rounded,
    this.emptyIcon = Icons.star_outline_rounded,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: nt.forest),
              const SizedBox(width: 8),
              Text(
                isRequired ? '$label *' : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: nt.bark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ...List.generate(5, (i) {
                final star = i + 1;
                // Inverted (Uncrowded): fill grows from the right (star > value).
                final filled = value != null &&
                    (inverted ? star > value! : star <= value!);
                final Color color;
                if (value == null) {
                  color = nt.border;
                } else if (inverted) {
                  // Tint every glyph (including empties) by the value.
                  color = nt.rating(value!.toDouble());
                } else {
                  color = filled
                      ? nt.rating(value!.toDouble())
                      : nt.border;
                }
                return GestureDetector(
                  onTap: () => onChanged(value == star ? null : star),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Icon(
                      filled ? filledIcon : emptyIcon,
                      size: 26,
                      color: color,
                    ),
                  ),
                );
              }),
              const Spacer(),
              Text(
                value != null ? '$value/5' : '—',
                style: value != null
                    ? TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: nt.rating(value!.toDouble()),
                      )
                    : TextStyle(fontSize: 16, color: nt.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

