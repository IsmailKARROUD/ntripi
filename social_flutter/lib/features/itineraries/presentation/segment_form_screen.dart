// presentation/segment_form_screen.dart — Create / edit a transit segment.
//
// Create: /itineraries/:id/segments/new
// Edit:   /itineraries/:id/segments/:segmentId/edit
//
// The user picks from/to stops from dropdowns, then builds a list of legs
// locally. On Save the full payload is sent as one request (full replace on
// edit, create on new).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_tile.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class SegmentFormScreen extends ConsumerStatefulWidget {
  final String itineraryId;
  final String? segmentId;
  final String? initialFromStopId;
  final String? initialToStopId;

  const SegmentFormScreen({
    super.key,
    required this.itineraryId,
    this.segmentId,
    this.initialFromStopId,
    this.initialToStopId,
  });

  @override
  ConsumerState<SegmentFormScreen> createState() => _SegmentFormScreenState();
}

class _SegmentFormScreenState extends ConsumerState<SegmentFormScreen> {
  String? _fromStopId;
  String? _toStopId;
  // Raw leg maps — positions are assigned on submit.
  List<Map<String, dynamic>> _legs = [];
  bool _initialized = false;
  bool _saving = false;

  bool get _isEdit => widget.segmentId != null;

  void _initFromSegment(TransitSegment segment) {
    _fromStopId = segment.fromStopId;
    _toStopId = segment.toStopId;
    _legs = segment.legs
        .map((l) => {
              'mode': l.mode.name,
              if (l.line != null) 'line': l.line,
              if (l.direction != null) 'direction': l.direction,
              if (l.notes != null) 'notes': l.notes,
              if (l.durationMin != null) 'duration_min': l.durationMin,
              'is_free': l.isFree,
              'cost': l.cost,
            })
        .toList();
    _initialized = true;
  }

  Future<void> _save(List<Stop> stops) async {
    if (_fromStopId == null || _toStopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select both a From and a To stop.')),
      );
      return;
    }
    if (_legs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one leg before saving.')),
      );
      return;
    }
    if (_fromStopId == _toStopId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('From and To stops must differ.')),
      );
      return;
    }

    final notifier =
        ref.read(itineraryDetailProvider(widget.itineraryId).notifier);
    final data = <String, dynamic>{
      'from_stop_id': _fromStopId,
      'to_stop_id': _toStopId,
      'legs': [
        for (var i = 0; i < _legs.length; i++)
          {..._legs[i], 'position': i + 1},
      ],
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await notifier.updateSegment(widget.segmentId!, data);
      } else {
        await notifier.createSegment(data);
      }
      if (!mounted) return;
      context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLeg() async {
    final result = await LegFormDialog.show(context);
    if (result != null) setState(() => _legs.add(result));
  }

  Future<void> _editLeg(int index) async {
    final existing = _legFromMap(_legs[index], index);
    final result = await LegFormDialog.show(context, existing: existing);
    if (result != null) setState(() => _legs[index] = result);
  }

  TransportLeg _legFromMap(Map<String, dynamic> data, int index) {
    return TransportLeg(
      id: 'local-$index',
      segmentId: '',
      position: index + 1,
      mode: TransportMode.values.firstWhere(
        (m) => m.name == (data['mode'] as String? ?? 'walk'),
        orElse: () => TransportMode.walk,
      ),
      line: data['line'] as String?,
      direction: data['direction'] as String?,
      notes: data['notes'] as String?,
      durationMin: data['duration_min'] as int?,
      cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
      isFree: data['is_free'] as bool? ?? false,
      createdAt: DateTime.now(),
    );
  }

  String _stopLabel(Stop s) {
    final name = s.placeName;
    if (name != null && name.isNotEmpty) return name;
    return '${s.type.name[0].toUpperCase()}${s.type.name.substring(1)} ${s.position}';
  }

  @override
  Widget build(BuildContext context) {
    final itineraryAsync =
        ref.watch(itineraryDetailProvider(widget.itineraryId));

    return itineraryAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(extractErrorMessage(e as dynamic))),
      ),
      data: (itinerary) {
        final stops = itinerary.stops;

        // One-time initialisation.
        if (!_initialized) {
          if (_isEdit) {
            final segment = itinerary.segments
                .where((s) => s.id == widget.segmentId)
                .firstOrNull;
            if (segment != null) _initFromSegment(segment);
          } else {
            _fromStopId = widget.initialFromStopId;
            _toStopId = widget.initialToStopId;
            _initialized = true;
          }
        }

        final eligibleTo =
            stops.where((s) => s.id != _fromStopId).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(_isEdit ? 'Edit Segment' : 'Add Segment'),
            actions: [
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _save(stops),
                  child: const Text('Save'),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // From stop
              DropdownButtonFormField<String>(
                value: _fromStopId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'From Stop',
                  border: OutlineInputBorder(),
                ),
                items: stops
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          _stopLabel(s),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _fromStopId = v;
                  if (_toStopId == v) _toStopId = null;
                }),
              ),
              const SizedBox(height: 12),

              // To stop
              DropdownButtonFormField<String>(
                value: _toStopId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'To Stop',
                  border: OutlineInputBorder(),
                ),
                items: eligibleTo
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          _stopLabel(s),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _toStopId = v),
              ),
              const SizedBox(height: 20),

              // Legs header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Legs',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  TextButton.icon(
                    onPressed: _addLeg,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Leg'),
                  ),
                ],
              ),

              if (_legs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No legs yet. Add at least one.',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ),
                )
              else
                for (var i = 0; i < _legs.length; i++)
                  LegTile(
                    key: ValueKey(i),
                    leg: _legFromMap(_legs[i], i),
                    onEdit: () => _editLeg(i),
                    onDelete: () => setState(() => _legs.removeAt(i)),
                  ),

              // Extra bottom padding so last leg isn't hidden behind keyboard.
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}
