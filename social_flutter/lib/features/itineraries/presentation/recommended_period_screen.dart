// presentation/recommended_period_screen.dart — "Best time to visit".
//
// Pushed via Navigator.push<RecommendedPeriod>. Pops with the edited value when
// the user taps Done, or null when they back out. Used from two places: the
// itinerary form's BASICS section (create and edit) and the detail screen's
// edit mode. Neither saves here — the caller owns the write, so this screen
// works identically before an itinerary id exists.
//
// The month GRID is the source of truth, not a list of windows. Windows are
// derived from the contiguous runs of selected months on every rebuild, which
// is what makes overlapping windows impossible: selecting Jan–Jun and then
// Mar–Jul is just the set {1…7}, so it collapses to one Jan–Jul window with no
// warning to dismiss. The backend enforces the same rule independently.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/recommended_period.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/moderation_hint.dart';

/// Any year works — none is stored. 2024 is a leap year so 29 Feb formats, and
/// 1 Jan 2024 was a Monday so DateTime(2024, 1, n).weekday == n for ISO 1..7.
const _formatYear = 2024;

class RecommendedPeriodScreen extends StatefulWidget {
  final RecommendedPeriod? initial;

  const RecommendedPeriodScreen({super.key, this.initial});

  @override
  State<RecommendedPeriodScreen> createState() =>
      _RecommendedPeriodScreenState();
}

class _RecommendedPeriodScreenState extends State<RecommendedPeriodScreen> {
  late Set<int> _months;
  late Set<int> _weekdays;
  late final TextEditingController _noteController;

  /// Exact-day refinements, keyed by the window's "fromMonth-toMonth" pair.
  ///
  /// Held apart from the windows because the windows are recomputed from
  /// [_months] on every rebuild. A refinement survives only while its key still
  /// exists: recomputing it against boundaries the author just moved would put
  /// dates on screen that they never chose.
  final Map<String, ({int? fromDay, int? toDay})> _dayRefinements = {};

  /// Baseline the unsaved-changes guard compares against. An absent initial
  /// value and an empty edited one are the same thing, so both normalize here.
  late final RecommendedPeriod _initial;

  /// Cached because [PopScope.canPop] is read from the tree: a keystroke in the
  /// note has to keep it fresh, but only a keystroke that actually flips
  /// dirtiness is worth a rebuild.
  bool _dirty = false;

  static String _key(PeriodWindow window) =>
      '${window.fromMonth}-${window.toMonth}';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _initial = initial ?? const RecommendedPeriod();
    _months = monthsFromWindows(initial?.windows ?? const []);
    _weekdays = {...?initial?.weekdays};
    _noteController = TextEditingController(text: initial?.note ?? '');
    for (final window in initial?.windows ?? const <PeriodWindow>[]) {
      if (!window.isWholeMonths) {
        _dayRefinements[_key(window)] =
            (fromDay: window.fromDay, toDay: window.toDay);
      }
    }
    _noteController.addListener(_refreshDirty);
  }

  @override
  void dispose() {
    _noteController.removeListener(_refreshDirty);
    _noteController.dispose();
    super.dispose();
  }

  /// The value this screen would return right now.
  RecommendedPeriod get _value {
    final note = _noteController.text.trim();
    return RecommendedPeriod(
      windows: _windows,
      weekdays: _weekdays.toList()..sort(),
      note: note.isEmpty ? null : note,
    );
  }

  /// Re-evaluates the guard after any edit. Compares by value, so toggling a
  /// month on and back off again correctly reads as "nothing changed".
  void _refreshDirty() {
    final dirty = _value != _initial;
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

  /// Windows derived from the grid, with any surviving day refinements applied.
  List<PeriodWindow> get _windows => [
        for (final window in windowsFromMonths(_months))
          if (_dayRefinements[_key(window)] case final days?)
            window.copyWith(fromDay: days.fromDay, toDay: days.toDay)
          else
            window,
      ];

  void _toggleMonth(int month) {
    setState(() {
      if (!_months.remove(month)) _months.add(month);
      // Drop refinements whose window no longer exists — see _dayRefinements.
      final live = windowsFromMonths(_months).map(_key).toSet();
      _dayRefinements.removeWhere((key, _) => !live.contains(key));
    });
    _refreshDirty();
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      if (!_weekdays.remove(weekday)) _weekdays.add(weekday);
    });
    _refreshDirty();
  }

  void _applyWeekdayPreset(Set<int> preset) {
    setState(() {
      // Tapping the active preset again clears it, so the control is a toggle
      // rather than a one-way door.
      _weekdays = setEqualsInts(_weekdays, preset) ? <int>{} : {...preset};
    });
    _refreshDirty();
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    // Wipes months, days, weekdays and the note in one tap with nothing to undo
    // — Tier 2 territory, so it asks first.
    final confirmed = await confirmDestructiveAction(
      context: context,
      icon: Icons.backspace_outlined,
      title: l10n.periodClearConfirmTitle,
      message: l10n.periodClearConfirmMessage,
      confirmLabel: l10n.periodClear,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _months.clear();
      _weekdays.clear();
      _dayRefinements.clear();
      _noteController.clear();
    });
    _refreshDirty();
  }

  Future<void> _editDays(PeriodWindow window) async {
    final result = await showModalBottomSheet<({int? fromDay, int? toDay})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExactDaysSheet(window: window),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.fromDay == null && result.toDay == null) {
        _dayRefinements.remove(_key(window));
      } else {
        _dayRefinements[_key(window)] = result;
      }
    });
    _refreshDirty();
  }

  // Navigator.pop is imperative and bypasses PopScope, so Done saves without
  // ever meeting the discard guard below — which only watches system back.
  void _done() => Navigator.pop(context, _value);

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final localeName = l10n.localeName;
    final windows = _windows;

    return PopScope(
      // Block the back gesture/button while there are unsaved edits; the
      // callback then offers a discard confirmation.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          // Pops with null — the caller reads that as "left untouched".
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      backgroundColor: nt.surface,
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: EditorialTopBar(
            title: l10n.bestTimeToVisit,
            actions: [
              TextButton(
                onPressed: _done,
                child: Text(
                  l10n.done,
                  style: TextStyle(
                    color: nt.forest,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        const EditorialDivider(),
        Expanded(child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ── Months grid ───────────────────────────────────────────────────
          SectionLabel(label: l10n.periodSectionMonths),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.periodMonthsHelp,
                  style: TextStyle(fontSize: 12, color: nt.text2),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.1,
                  children: [
                    for (var month = 1; month <= 12; month++)
                      _ToggleCell(
                        label: intl.DateFormat.MMM(localeName)
                            .format(DateTime(_formatYear, month)),
                        selected: _months.contains(month),
                        onTap: () => _toggleMonth(month),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Derived windows ───────────────────────────────────────────────
          SectionLabel(label: l10n.periodSectionWindows),
          _SectionCard(
            child: windows.isEmpty
                ? Text(
                    l10n.periodNoMonthsSelected,
                    style: TextStyle(fontSize: 13, color: nt.text3),
                  )
                : Column(
                    children: [
                      for (final window in windows)
                        _WindowRow(
                          label: window.label(localeName),
                          refined: !window.isWholeMonths,
                          onTap: () => _editDays(window),
                        ),
                    ],
                  ),
          ),

          // ── Weekdays ──────────────────────────────────────────────────────
          SectionLabel(label: l10n.periodSectionWeekdays),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final weekday in _orderedWeekdays(context))
                      _ToggleChip(
                        label: intl.DateFormat.E(localeName)
                            .format(DateTime(_formatYear, 1, weekday)),
                        selected: _weekdays.contains(weekday),
                        onTap: () => _toggleWeekday(weekday),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _PresetChip(
                      label: l10n.periodWeekdays,
                      selected: setEqualsInts(_weekdays, const {1, 2, 3, 4, 5}),
                      onTap: () => _applyWeekdayPreset(const {1, 2, 3, 4, 5}),
                    ),
                    _PresetChip(
                      label: l10n.periodWeekends,
                      selected: setEqualsInts(_weekdays, const {6, 7}),
                      onTap: () => _applyWeekdayPreset(const {6, 7}),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Why ───────────────────────────────────────────────────────────
          SectionLabel(label: l10n.periodSectionWhy),
          _SectionCard(
            // Free prose, which is exactly the client filter's scope. It warns
            // and nothing more: Done above stays enabled either way, and the
            // months and weekdays are never filtered.
            child: ModerationHint(
              controller: _noteController,
              child: TextField(
                controller: _noteController,
                maxLength: 200,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  counterStyle: TextStyle(color: nt.text3, fontSize: 11),
                  hintText: l10n.periodWhyHint,
                  hintStyle:
                      TextStyle(color: nt.text3, fontWeight: FontWeight.w500),
                ),
                style: TextStyle(fontSize: 14, color: nt.bark),
              ),
            ),
          ),

          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              // Nothing to clear, nothing to confirm — don't offer the action.
              onPressed: _value.isEmpty ? null : _clearAll,
              icon: Icon(Icons.backspace_outlined, size: 16, color: nt.text2),
              label: Text(
                l10n.periodClear,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: nt.text2,
                ),
              ),
            ),
          ),
          ],
        )),
      ]),
      ),
    );
  }

  /// ISO weekdays rotated so the locale's own first day leads (Sunday-first in
  /// en_US, Monday-first in fr, Saturday-first in ar).
  List<int> _orderedWeekdays(BuildContext context) {
    // MaterialLocalizations indexes Sunday as 0; ISO numbers Sunday as 7.
    final firstIndex = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final firstIso = firstIndex == 0 ? 7 : firstIndex;
    return [for (var i = 0; i < 7; i++) (firstIso - 1 + i) % 7 + 1];
  }
}

// ─── Exact-days sheet ─────────────────────────────────────────────────────────
// Refines one window's first and last month to an exact day. Both are optional
// and independently clearable, and a refinement can only ever move a boundary
// INWARD within that window's own months — so it can never reach a neighbour
// and reintroduce an overlap.
class _ExactDaysSheet extends StatefulWidget {
  final PeriodWindow window;

  const _ExactDaysSheet({required this.window});

  @override
  State<_ExactDaysSheet> createState() => _ExactDaysSheetState();
}

class _ExactDaysSheetState extends State<_ExactDaysSheet> {
  late int? _fromDay = widget.window.fromDay;
  late int? _toDay = widget.window.toDay;

  /// A single-month window is a plain range, so a start after the end would be
  /// nonsense (20 Jun → 10 Jun). Mirrors the backend's same-month rule.
  bool get _valid =>
      widget.window.fromMonth != widget.window.toMonth ||
      _fromDay == null ||
      _toDay == null ||
      _fromDay! <= _toDay!;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final localeName = l10n.localeName;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: nt.text3.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.periodExactDays,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: nt.bark,
              ),
            ),
            const SizedBox(height: 16),
            _DayPickerRow(
              label: l10n.periodStartsOn,
              month: widget.window.fromMonth,
              day: _fromDay,
              localeName: localeName,
              onChanged: (day) => setState(() => _fromDay = day),
            ),
            const SizedBox(height: 12),
            _DayPickerRow(
              label: l10n.periodEndsOn,
              month: widget.window.toMonth,
              day: _toDay,
              localeName: localeName,
              onChanged: (day) => setState(() => _toDay = day),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop<({int? fromDay, int? toDay})>(
                      context,
                      (fromDay: null, toDay: null),
                    ),
                    child: Text(
                      l10n.periodClear,
                      style: TextStyle(color: nt.text2),
                    ),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: _valid
                        ? () => Navigator.pop<({int? fromDay, int? toDay})>(
                              context,
                              (fromDay: _fromDay, toDay: _toDay),
                            )
                        : null,
                    child: Text(l10n.done),
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

class _DayPickerRow extends StatelessWidget {
  final String label;
  final int month;
  final int? day;
  final String localeName;
  final ValueChanged<int?> onChanged;

  const _DayPickerRow({
    required this.label,
    required this.month,
    required this.day,
    required this.localeName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final monthName =
        intl.DateFormat.MMMM(localeName).format(DateTime(_formatYear, month));

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: nt.text2,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                monthName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: nt.bark,
                ),
              ),
            ],
          ),
        ),
        DropdownButton<int?>(
          value: day,
          underline: const SizedBox.shrink(),
          hint: Text(
            l10n.periodWholeMonth,
            style: TextStyle(fontSize: 13, color: nt.text3),
          ),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text(
                l10n.periodWholeMonth,
                style: TextStyle(fontSize: 13, color: nt.text2),
              ),
            ),
            // daysInMonth puts February at 29 — a window carries no year, so the
            // leap day is a real choice rather than an off-by-one.
            for (var d = 1; d <= daysInMonth(month); d++)
              DropdownMenuItem<int?>(value: d, child: Text('$d')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─── Screen-private widgets ───────────────────────────────────────────────────


// Padded single-child variant of the shared SectionCard — this screen's
// sections are prose and grids, not rows, so they need the inner padding that
// row widgets supply themselves. Delegates so card styling has one home.
class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) => SectionCard(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Padding(padding: const EdgeInsets.all(14), child: child)],
      );
}

class _ToggleCell extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? nt.forest : nt.mist,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? nt.forest : nt.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? nt.surface : nt.bark,
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? nt.forest : nt.mist,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? nt.forest : nt.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? nt.surface : nt.bark,
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? nt.editBlueTint : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? nt.editBlue : nt.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? nt.editBlue : nt.text2,
          ),
        ),
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  final String label;
  final bool refined;
  final VoidCallback onTap;

  const _WindowRow({
    required this.label,
    required this.refined,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: nt.bark,
                ),
              ),
            ),
            Icon(
              refined ? Icons.edit_calendar_rounded : Icons.date_range_rounded,
              size: 16,
              color: refined ? nt.editBlue : nt.text3,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.periodExactDays,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: refined ? nt.editBlue : nt.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
