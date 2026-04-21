// widgets/leg_form_dialog.dart — Bottom sheet for adding / editing a transport leg.
//
// Usage: await LegFormDialog.show(context) — returns Map<String,dynamic>? with
//   keys: mode, line?, direction?, notes?, duration_min?, is_free, cost?
// Returns null if the user dismisses without saving.
//
// Line / Direction visibility: only shown for transit modes that use numbered
//   lines (bus, tram, metro, train, ferry). Hidden for walk, car, bike, uber, taxi.
//
// Duration entry: two fields (h + min) combined into duration_min on submit.
//   Easier than typing raw minutes for long durations (e.g. 1h 30min vs 90).
//
// isScrollControlled: true is required so the sheet can resize when the
// keyboard appears and the cost/notes fields stay visible.

import 'package:flutter/material.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

// Modes that use numbered/named transit lines and directions.
const _transitLineModes = {
  TransportMode.bus,
  TransportMode.tram,
  TransportMode.metro,
  TransportMode.train,
  TransportMode.ferry,
  TransportMode.airplane,
};

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
    // Combine h + min fields into a single duration_min value.
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
            isEdit ? 'Edit Leg' : 'Add Leg',
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Duration (h + min) + Cost
          Row(
            children: [
              // Hours field
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _durationHCtrl,
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cost',
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
            title: const Text('Free'),
            contentPadding: EdgeInsets.zero,
          ),

          // Notes
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          FilledButton(
            onPressed: _submit,
            child: Text(isEdit ? 'Update Leg' : 'Add Leg'),
          ),
        ],
      ),
    );
  }
}
