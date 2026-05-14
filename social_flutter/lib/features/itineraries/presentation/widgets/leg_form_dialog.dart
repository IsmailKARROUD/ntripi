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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

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
    // Allow empty
    if (newValue.text.isEmpty) return newValue;

    // Accept if matches the regex
    if (regex.hasMatch(newValue.text)) return newValue;

    // Reject the change — keep old value
    return oldValue;
  }
}
class LegFormDialog extends StatefulWidget {
  final TransportLeg? existing;

  const LegFormDialog({super.key, this.existing});

  /// Open the bottom sheet and return the leg data map, or null if cancelled.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    TransportLeg? existing,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LegFormDialog(existing: existing),
    );
  }

  @override
  State<LegFormDialog> createState() => _LegFormDialogState();
}

class _LegFormDialogState extends State<LegFormDialog> {
  late TransportMode _mode;
  late TextEditingController _lineCtrl;
  late TextEditingController _directionCtrl;
  late TextEditingController _notesCtrl;
  // Duration stored as two separate fields; combined to duration_min on submit.
  late TextEditingController _durationHCtrl;
  late TextEditingController _durationMinCtrl;
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

    // Split existing duration_min into hours + minutes for display.
    final dMin = e?.durationMin;
    _durationHCtrl = TextEditingController(
      text: dMin != null && dMin >= 60 ? '${dMin ~/ 60}' : '',
    );
    _durationMinCtrl = TextEditingController(
      text: dMin != null && dMin % 60 > 0 ? '${dMin % 60}' : '',
    );

    _costCtrl = TextEditingController(
      text: (e != null && !e.isFree && e.cost > 0)
          ? e.cost.toStringAsFixed(2)
          : '',
    );
    _isFree = e?.isFree ?? false;
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    _directionCtrl.dispose();
    _notesCtrl.dispose();
    _durationHCtrl.dispose();
    _durationMinCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final h = int.tryParse(_durationHCtrl.text.trim()) ?? 0;
    final m = int.tryParse(_durationMinCtrl.text.trim()) ?? 0;
    final totalMin = h * 60 + m;

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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(
            isEdit ? 'Edit Transit' : 'Add Transit',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Mode dropdown
          DropdownButtonFormField<TransportMode>(
            value: _mode,
            decoration: const InputDecoration(
              labelText: 'Mode',
              suffixIcon: FieldHelpIcon(
                helpTitle: 'Transport mode',
                helpMessage:
                    'How you travel on this leg (walk, bus, train, ferry, etc.). Some modes reveal extra fields for line and direction.',
              ),
              border: OutlineInputBorder(),
            ),
            items: TransportMode.values
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        Icon(m.icon, size: 18),
                        const SizedBox(width: 8),
                        Text(m.label),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _mode = v!),
          ),
          const SizedBox(height: 12),

          // Line + Direction — only for modes that use transit lines.
          if (_showTransitLine) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lineCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Line (optional)',
                      suffixIcon: FieldHelpIcon(
                        helpTitle: 'Line',
                        helpMessage:
                            'Optional. The line number or name (e.g. "Bus 42", "M1").',
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _directionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Direction (optional)',
                      suffixIcon: FieldHelpIcon(
                        helpTitle: 'Direction',
                        helpMessage:
                            'Optional. Where the line is headed (e.g. "Northbound", "Châtelet").',
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Duration (h + min) + Cost — help icons sit on the section header
          // above; the narrow h/min fields keep their short labels for space.
          const Row(
            children: [
              LabelWithHelp(
                label: 'Duration',
                helpTitle: 'Duration',
                helpMessage:
                    'How long this leg takes in hours and minutes.',
              ),
              Spacer(),
              LabelWithHelp(
                label: 'Cost',
                helpTitle: 'Cost',
                helpMessage:
                    "Approximate cost in the itinerary's currency. Disabled when \"Free\" is on.",
              ),
              SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Hours field
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _durationHCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'h',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Minutes field
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _durationMinCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'min',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Cost field
              Expanded(
                child: TextField(
                  controller: _costCtrl,
                  enabled: !_isFree,
                  inputFormatters: [
                    RegexInputFormatter(RegExp(r'^\d{0,8}(\.\d{0,2})?$')),
                  ],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          SwitchListTile.adaptive(
            value: _isFree,
            onChanged: (v) => setState(() => _isFree = v),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Free'),
                SizedBox(width: 2),
                FieldHelpIcon(
                  helpTitle: 'Free',
                  helpMessage:
                      'Toggle on if this leg costs nothing (walking, included transfer, etc.).',
                ),
              ],
            ),
            contentPadding: EdgeInsets.zero,
          ),

          // Thoughts (renamed from Notes)
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Thoughts (optional)',
              suffixIcon: FieldHelpIcon(
                helpTitle: 'Thoughts',
                helpMessage:
                    'Optional. Anything useful to know about this leg — booking tips, transfer instructions, where to sit, ticket cost surprises.',
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              if (isEdit)
                TextButton(
                  onPressed: _deleteLeg,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: Text(isEdit ? 'Update Transit' : 'Add Transit'),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
