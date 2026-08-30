// widgets/leg_form_dialog.dart — Bottom sheet for adding / editing a transport leg.
//
// Return values:
//   null                      → user cancelled (dismiss or Cancel button)
//   {'__action': 'delete'}    → user tapped Delete (sentinel; no leg fields)
//   {mode, line?, ...}        → user saved; ready to send to the API
//
// Line / Direction fields are shown only for modes that use numbered lines
//   (bus, tram, metro, train, ferry, airplane). Hidden for walk, car, bike, taxi, uber.
//
// Duration is split into two fields (h + min) and combined to duration_min on
//   submit — typing "90" as raw minutes is error-prone for long trips.
//
// isScrollControlled: true keeps the cost/notes fields above the keyboard.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/ui/toggle_feedback.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

// Modes that use numbered/named transit lines and directions.
const _transitLineModes = {
  TransportMode.bus,
  TransportMode.tram,
  TransportMode.metro,
  TransportMode.train,
  TransportMode.ferry,
  TransportMode.airplane,
};

class RegexInputFormatter extends TextInputFormatter {
  final RegExp regex;

  RegexInputFormatter(this.regex);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    if (regex.hasMatch(newValue.text)) return newValue;
    return oldValue;
  }
}

class LegFormDialog extends ConsumerStatefulWidget {
  final TransportLeg? existing;

  const LegFormDialog({super.key, this.existing});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    TransportLeg? existing,
  }) {
    final nt = context.nt;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: nt.sand,
      builder: (_) => LegFormDialog(existing: existing),
    );
  }

  @override
  ConsumerState<LegFormDialog> createState() => _LegFormDialogState();
}

class _LegFormDialogState extends ConsumerState<LegFormDialog> {
  late TransportMode _mode;
  late TextEditingController _lineCtrl;
  late TextEditingController _directionCtrl;
  late TextEditingController _notesCtrl;
  int _durationDays = 0;
  int _durationHours = 0;
  int _durationMinutes = 0;
  late TextEditingController _costCtrl;
  late bool _isFree;

  // Hides line/direction fields for modes that don't use numbered routes.
  bool get _showTransitLine => _transitLineModes.contains(_mode);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _mode = e?.mode ?? TransportMode.walk;
    _lineCtrl = TextEditingController(text: e?.line ?? '');
    _directionCtrl = TextEditingController(text: e?.direction ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');

    // Split existing duration_min into days + hours + minutes for the picker.
    final dMin = e?.durationMin ?? 0;
    _durationDays = dMin ~/ (24 * 60);
    _durationHours = (dMin % (24 * 60)) ~/ 60;
    _durationMinutes = dMin % 60;

    _costCtrl = TextEditingController(
      text: (e != null && !e.isFree && e.cost > 0)
          ? e.cost.toStringAsFixed(2)
          : '',
    );
    _isFree = e?.isFree ?? false;
    // Baseline of all fields, captured after seeding from widget.existing, so
    // dismissing without changes does not trigger the discard confirmation.
    _initialSnapshot = _snapshot();
  }

  // Baseline of all user-editable fields for unsaved-change detection.
  List<Object?>? _initialSnapshot;

  List<Object?> _snapshot() => [
        _mode,
        _lineCtrl.text,
        _directionCtrl.text,
        _notesCtrl.text,
        _durationDays,
        _durationHours,
        _durationMinutes,
        _costCtrl.text,
        _isFree,
      ];

  bool get _isDirty {
    final base = _initialSnapshot;
    if (base == null) return false;
    final now = _snapshot();
    if (now.length != base.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (now[i] != base[i]) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final l10n = AppLocalizations.of(context)!;
    return confirmDestructiveAction(
      context: context,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discardButton,
      cancelLabel: l10n.keepEditingButton,
    );
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    _directionCtrl.dispose();
    _notesCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  String get _durationLabel {
    final parts = <String>[
      if (_durationDays > 0) '${_durationDays}d',
      if (_durationHours > 0) '${_durationHours}h',
      if (_durationMinutes > 0)
        '${_durationMinutes.toString().padLeft(2, '0')}min',
    ];
    return parts.isEmpty ? AppLocalizations.of(context)!.notSet : parts.join(' ');
  }

  Future<void> _showDurationPicker() async {
    if (!mounted) return;
    int tempDays = _durationDays;
    int tempHours = _durationHours;
    int tempMinutes = _durationMinutes;

    final daysCtrl = FixedExtentScrollController(initialItem: tempDays);
    final hoursCtrl = FixedExtentScrollController(initialItem: tempHours);
    final minsCtrl = FixedExtentScrollController(initialItem: tempMinutes);

    final l10n = AppLocalizations.of(context)!;

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.cancel),
                    ),
                    Text(
                      l10n.durationLabel,
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _durationDays = tempDays;
                          _durationHours = tempHours;
                          _durationMinutes = tempMinutes;
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.doneTooltip),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: daysCtrl,
                        itemExtent: 44,
                        onSelectedItemChanged: (i) => tempDays = i,
                        children: List.generate(
                          366,
                          (i) => Center(child: Text('$i ${AppLocalizations.of(context)!.daysLabel}')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: hoursCtrl,
                        itemExtent: 44,
                        onSelectedItemChanged: (i) => tempHours = i,
                        children: List.generate(
                          24,
                          (i) => Center(child: Text('$i ${AppLocalizations.of(context)!.hoursLabel}')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: minsCtrl,
                        itemExtent: 44,
                        onSelectedItemChanged: (i) => tempMinutes = i,
                        children: List.generate(
                          60,
                          (i) => Center(
                            child: Text(
                                '${i.toString().padLeft(2, '0')} min'),
                          ),
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

    daysCtrl.dispose();
    hoursCtrl.dispose();
    minsCtrl.dispose();
  }

  void _submit() {
    final totalMin =
        _durationDays * 24 * 60 + _durationHours * 60 + _durationMinutes;

    final data = <String, dynamic>{
      'mode': _mode.name,
      if (_showTransitLine && _lineCtrl.text.trim().isNotEmpty)
        'line': _lineCtrl.text.trim(),
      if (_showTransitLine && _directionCtrl.text.trim().isNotEmpty)
        'direction': _directionCtrl.text.trim(),
      if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      if (totalMin > 0) 'duration_min': totalMin,
      'is_free': _isFree,
      if (!_isFree && _costCtrl.text.trim().isNotEmpty)
        'cost': double.tryParse(_costCtrl.text.trim()) ?? 0.0,
    };
    Navigator.of(context).pop(data);
  }

  // Pops with a sentinel so the caller can distinguish delete from cancel
  // without changing the Future<Map?> return type of show().
  void _deleteLeg() =>
      Navigator.of(context).pop(const {'__action': 'delete'});

  Future<void> _showModePicker() async {
    final nt = context.nt;
    if (!mounted) return;
    final currentMode = _mode;
    final picked = await showModalBottomSheet<TransportMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: nt.sand,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SectionLabel(
                  label: AppLocalizations.of(ctx)!.transportModeSection),
              // Flexible lets the card fill remaining sheet space and scroll.
              Flexible(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  decoration: BoxDecoration(
                    color: nt.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: nt.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: TransportMode.values.length,
                    separatorBuilder: (_, __) => Container(
                      height: 1,
                      color: nt.border,
                      margin: const EdgeInsetsDirectional.only(start: 16),
                    ),
                    itemBuilder: (_, i) {
                      final mode = TransportMode.values[i];
                      return InkWell(
                        onTap: () => Navigator.of(ctx).pop(mode),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: nt.mist,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Icon(mode.icon, size: 16, color: nt.forest),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  mode.label(AppLocalizations.of(ctx)!),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: nt.bark,
                                  ),
                                ),
                              ),
                              if (currentMode == mode)
                                Icon(Icons.check_rounded,
                                    size: 18, color: nt.forest),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _mode = picked);
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final isEdit = widget.existing != null;
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      // Block drag-down dismiss while there are unsaved edits; the callback
      // then offers a discard confirmation. Save/Delete pop directly and are
      // unaffected.
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop(); // null result == cancel, matches contract
        }
      },
      child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── TRANSPORT MODE ─────────────────────────────────────────────
            SectionLabel(label: l10n.transportModeSection),
            SectionCard(
              clipBehavior: Clip.antiAlias,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LFPickerRow(
                  icon: _mode.icon,
                  label: l10n.transportModeLabel.toUpperCase(),
                  value: _mode.label(l10n),
                  onTap: _showModePicker,
                ),
              ],
            ),

            // ── LINE & DIRECTION (transit modes only) ──────────────────────
            if (_showTransitLine) ...[
              SectionLabel(label: l10n.lineDirectionSection),
              SectionCard(
              clipBehavior: Clip.antiAlias,
              crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LFBorderlessField(
                    label: l10n.transitLineLabel.toUpperCase(),
                    child: TextField(
                      controller: _lineCtrl,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: '—',
                      ),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: nt.bark),
                    ),
                  ),
                  const FieldDivider(),
                  _LFBorderlessField(
                    label: l10n.transitDirectionLabel.toUpperCase(),
                    child: TextField(
                      controller: _directionCtrl,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: '—',
                      ),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: nt.bark),
                    ),
                  ),
                ],
              ),
            ],

            // ── DURATION & COST ────────────────────────────────────────────
            SectionLabel(label: l10n.durationCostSection),
            SectionCard(
              clipBehavior: Clip.antiAlias,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LFPickerRow(
                  icon: Icons.schedule_rounded,
                  label: l10n.durationLabel.toUpperCase(),
                  value: _durationLabel,
                  onTap: _showDurationPicker,
                ),
                const FieldDivider(),

                // Free toggle row
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: nt.mist,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.payments_rounded,
                            size: 16, color: nt.forest),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.costLabel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: nt.text2,
                                letterSpacing: 0.4,
                              ),
                            ),
                            Text(
                              l10n.freeLegLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: nt.bark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isFree,
                        onChanged: (v) {
                          setState(() {
                            _isFree = v;
                            if (v) _costCtrl.clear();
                          });
                          toggleFeedback(ref);
                        },
                        activeThumbColor: nt.forest,
                        activeTrackColor: nt.mist,
                      ),
                    ],
                  ),
                ),

                // Cost amount field — hidden when free
                if (!_isFree) ...[
                  const FieldDivider(),
                  _LFBorderlessField(
                    label: l10n.costLabel.toUpperCase(),
                    child: TextField(
                      controller: _costCtrl,
                      inputFormatters: [
                        RegexInputFormatter(
                            RegExp(r'^\d{0,8}(\.\d{0,2})?$')),
                      ],
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: AppLocalizations.of(context)!.legCostHint,
                      ),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: nt.bark),
                    ),
                  ),
                ],
              ],
            ),

            // ── THOUGHTS ──────────────────────────────────────────────────
            SectionLabel(label: l10n.thoughtsLabel),
            SectionCard(
              clipBehavior: Clip.antiAlias,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: l10n.legThoughtsLabel,
                      hintStyle: TextStyle(color: nt.text3),
                    ),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: nt.bark),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Buttons ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  if (isEdit)
                    TextButton(
                      onPressed: _deleteLeg,
                      style: TextButton.styleFrom(
                          foregroundColor: nt.danger),
                      child: Text(l10n.deleteButton),
                    ),
                  const Spacer(),
                  TextButton(
                    // Route through the discard guard so Cancel and drag-down
                    // dismiss behave identically.
                    onPressed: () async {
                      if (await _confirmDiscard() && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: TextButton.styleFrom(foregroundColor: nt.forest),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
                      child: Text(isEdit
                          ? l10n.updateTransitButton
                          : l10n.addTransitTitle),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }
}

// ── Local editorial helpers ───────────────────────────────────────────────────




class _LFBorderlessField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LFBorderlessField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
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
            const SizedBox(height: 4),
            child,
          ],
        ),
      );
  }
}

class _LFPickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _LFPickerRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: nt.mist,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: nt.forest),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: nt.bark,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 20, color: nt.text3),
            ],
          ),
        ),
      );
  }
}
