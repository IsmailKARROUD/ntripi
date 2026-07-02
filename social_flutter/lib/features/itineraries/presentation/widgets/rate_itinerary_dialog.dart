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
import 'package:social_flutter/shared/widgets/loaders.dart';

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
    setState(() => _saving = true);
    try {
      await widget.parentRef
          .read(myRatingProvider(widget.itineraryId).notifier)
          .deleteRating();
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
      );
    }
  }

  Future<void> _save() async {
    if (_overall == null) return;
    setState(() => _saving = true);
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
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSave = _overall != null && !_saving;

    return SingleChildScrollView(
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
                color: kText3.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Hint text
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Text(
              'Rate your overall impression. Once you do, you can share more.',
              style: const TextStyle(fontSize: 12, color: kText2),
            ),
          ),

          // ── Overall rating (required) ────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: _RatingSliderRow(
              icon: Icons.star_rounded,
              label: l10n.overallRatingLabel,
              isRequired: true,
              value: _overall,
              onChanged: (v) => setState(() => _overall = v),
            ),
          ),

          // ── Your review (optional) ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: const Text(
              'YOUR REVIEW (OPTIONAL)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kText2,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: MarkdownNotesEditor(
                controller: _noteController,
                readOnly: false,
                label: l10n.yourImpressionLabel,
                helpTitle: l10n.yourImpressionLabel,
                helpMessage: l10n.yourImpressionHelp,
              ),
            ),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text(
                          l10n.wantToShareMore.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kText2,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kBorder),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _RatingSliderRow(
                              icon: Icons.shield_outlined,
                              label: l10n.safetyLabel,
                              value: _safety,
                              onChanged: (v) => setState(() => _safety = v),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            _RatingSliderRow(
                              icon: Icons.emoji_emotions_outlined,
                              label: l10n.experienceLabel,
                              value: _experience,
                              onChanged: (v) => setState(() => _experience = v),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            _RatingSliderRow(
                              icon: Icons.accessible_outlined,
                              label: l10n.accessibilityLabel,
                              value: _accessibility,
                              onChanged: (v) =>
                                  setState(() => _accessibility = v),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            _RatingSliderRow(
                              icon: Icons.family_restroom_outlined,
                              label: l10n.familyFriendlyLabel,
                              value: _familyFriendly,
                              onChanged: (v) =>
                                  setState(() => _familyFriendly = v),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
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
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: l10n.removeMyRatingTooltip,
                    onPressed: _saving ? null : _deleteRating,
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
                  child: FilledButton(
                    onPressed: canSave ? _save : null,
                    child: _saving
                        ? const NTripiRingLoader(size: 18)
                        : Text(l10n.saveButton),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: kForest),
              const SizedBox(width: 8),
              Text(
                isRequired ? '$label *' : label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kBark,
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
                  color = const Color(0xFFE4E4E4);
                } else if (inverted) {
                  // Tint every glyph (including empties) by the value.
                  color = ratingColor(value!.toDouble());
                } else {
                  color = filled
                      ? ratingColor(value!.toDouble())
                      : const Color(0xFFE4E4E4);
                }
                return GestureDetector(
                  onTap: () => onChanged(value == star ? null : star),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
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
                        color: ratingColor(value!.toDouble()),
                      )
                    : const TextStyle(fontSize: 16, color: kText3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

