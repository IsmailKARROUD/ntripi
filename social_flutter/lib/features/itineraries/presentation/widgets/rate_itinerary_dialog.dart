// features/itineraries/presentation/widgets/rate_itinerary_dialog.dart
//
// Bottom-sheet dialog matching the "Rate this itinerary" mockup:
//   • Overall stars (required) — shows a thank-you line once tapped
//   • "Want to share more?" section (optional) — Safety, Experience,
//     Accessibility, Family-friendly sub-ratings
//   • Save / Cancel action buttons

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/my_rating.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
    _noteController.text = widget.current?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _deleteRating() async {
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: 'Remove your rating?',
      message: 'Your rating will be deleted and the average will update '
          'for everyone viewing this itinerary.',
      confirmLabel: 'Remove',
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
        SnackBar(content: Text(extractErrorMessage(e))),
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
            note: trimmedNote.isEmpty ? null : trimmedNote,
          ));
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _overall != null && !_saving;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text('Rate this itinerary', style: theme.textTheme.titleMedium),
          const SizedBox(height: 20),

          // Overall — required
          LabelWithHelp(
            label: 'Overall *',
            helpTitle: 'Overall rating',
            helpMessage:
                'Required. Your overall rating of this itinerary, from 1 to 5 stars.',
            labelStyle: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _StarRow(
            value: _overall,
            onChanged: (v) => setState(() => _overall = v),
          ),

          // Thank-you confirmation — appears once overall is set
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _overall != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          'Thanks! Your rating helps others.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.green.shade700),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Optional sub-ratings — only shown after overall is selected
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _overall != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _OptionalSection(
                      safety: _safety,
                      experience: _experience,
                      accessibility: _accessibility,
                      familyFriendly: _familyFriendly,
                      onSafetyChanged: (v) => setState(() => _safety = v),
                      onExperienceChanged: (v) => setState(() => _experience = v),
                      onAccessibilityChanged: (v) =>
                          setState(() => _accessibility = v),
                      onFamilyFriendlyChanged: (v) =>
                          setState(() => _familyFriendly = v),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Optional Markdown note — only shown after overall is selected
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _overall != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: MarkdownNotesEditor(
                      controller: _noteController,
                      readOnly: false,
                      label: 'Your impression (optional)',
                      helpTitle: 'Your impression',
                      helpMessage:
                          "Optional. Share what stood out — highlights, regrets, who you'd recommend it to. Use the toolbar to add bold, italic, headings, or bullet lists.",
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              if (widget.current != null) ...[
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  tooltip: 'Remove my rating',
                  onPressed: _saving ? null : _deleteRating,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Optional "Want to share more?" section
// ---------------------------------------------------------------------------

class _OptionalSection extends StatelessWidget {
  final int? safety;
  final int? experience;
  final int? accessibility;
  final int? familyFriendly;
  final ValueChanged<int?> onSafetyChanged;
  final ValueChanged<int?> onExperienceChanged;
  final ValueChanged<int?> onAccessibilityChanged;
  final ValueChanged<int?> onFamilyFriendlyChanged;

  const _OptionalSection({
    required this.safety,
    required this.experience,
    required this.accessibility,
    required this.familyFriendly,
    required this.onSafetyChanged,
    required this.onExperienceChanged,
    required this.onAccessibilityChanged,
    required this.onFamilyFriendlyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Want to share more? (optional)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            _SubRatingRow(
              label: 'Safety',
              helpTitle: 'Safety',
              helpMessage:
                  'Optional. How safe you felt during this trip.',
              value: safety,
              onChanged: onSafetyChanged,
            ),
            const SizedBox(height: 12),
            _SubRatingRow(
              label: 'Experience',
              helpTitle: 'Experience',
              helpMessage:
                  'Optional. How enjoyable and memorable the trip was.',
              value: experience,
              onChanged: onExperienceChanged,
            ),
            const SizedBox(height: 12),
            _SubRatingRow(
              label: 'Accessibility',
              helpTitle: 'Accessibility',
              helpMessage:
                  'Optional. How accessible the itinerary is (mobility, language, signage).',
              value: accessibility,
              onChanged: onAccessibilityChanged,
            ),
            const SizedBox(height: 12),
            _SubRatingRow(
              label: 'Family-friendly',
              helpTitle: 'Family-friendly',
              helpMessage:
                  'Optional. How suitable the trip is for families with children.',
              value: familyFriendly,
              onChanged: onFamilyFriendlyChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubRatingRow extends StatelessWidget {
  final String label;
  final String helpTitle;
  final String helpMessage;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _SubRatingRow({
    required this.label,
    required this.helpTitle,
    required this.helpMessage,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: LabelWithHelp(
            label: label,
            helpTitle: helpTitle,
            helpMessage: helpMessage,
            labelStyle: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        _StarRow(value: value, onChanged: onChanged, starSize: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable star row — tapping the current star deselects it (toggles off)
// ---------------------------------------------------------------------------

class _StarRow extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final double starSize;

  const _StarRow({
    required this.value,
    required this.onChanged,
    this.starSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final star = i + 1;
        final filled = value != null && star <= value!;
        return GestureDetector(
          onTap: () => onChanged(value == star ? null : star),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: starSize,
              color: filled ? ratingColor(value!.toDouble()) : Colors.grey.shade400,
            ),
          ),
        );
      }),
    );
  }
}
