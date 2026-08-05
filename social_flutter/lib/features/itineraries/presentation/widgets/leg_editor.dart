// widgets/leg_editor.dart — Shared transport-leg mutation logic.
//
// Extracted from SegmentCard when the stop detail screen gained a long-press
// edit path on its transit rows: there are no per-leg endpoints, so every
// add/edit/delete is a full-replace PATCH of the whole segment and that
// payload-building must not be duplicated per call site.
//
// Stateless by design — callers own their own saving/mounted state and pass a
// [onSavingChanged] hook if they render a spinner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/leg_form_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class LegEditor {
  final WidgetRef ref;
  final String itineraryId;
  final TransitSegment segment;

  /// Fired around the PATCH so a caller can render a spinner. Optional.
  final ValueChanged<bool>? onSavingChanged;

  const LegEditor({
    required this.ref,
    required this.itineraryId,
    required this.segment,
    this.onSavingChanged,
  });

  // Converts a domain leg to the raw map format the PATCH endpoint expects.
  // Null fields are omitted so the backend doesn't overwrite them with nulls.
  static Map<String, dynamic> legToMap(TransportLeg leg) => {
        'mode': leg.mode.name,
        if (leg.line != null) 'line': leg.line,
        if (leg.direction != null) 'direction': leg.direction,
        if (leg.notes != null) 'notes': leg.notes,
        if (leg.durationMin != null) 'duration_min': leg.durationMin,
        'is_free': leg.isFree,
        'cost': leg.cost,
      };

  // Positions are always re-assigned from scratch (1-based) so order in the
  // list is the single source of truth — no stale position values leak through.
  Map<String, dynamic> _buildPayload(List<Map<String, dynamic>> legMaps) => {
        'from_stop_id': segment.fromStopId,
        'to_stop_id': segment.toStopId,
        'legs': [
          for (var i = 0; i < legMaps.length; i++)
            {...legMaps[i], 'position': i + 1},
        ],
      };

  // Every leg change (add / edit / delete) goes through a full-replace PATCH —
  // there are no individual leg endpoints, so we always send the complete list.
  Future<void> saveLegs(
    BuildContext context,
    List<Map<String, dynamic>> updatedLegs,
  ) async {
    onSavingChanged?.call(true);
    try {
      await ref
          .read(itineraryDetailProvider(itineraryId).notifier)
          .updateSegment(segment.id, _buildPayload(updatedLegs));
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              extractErrorMessage(e as dynamic, AppLocalizations.of(context)!)),
        ),
      );
    } finally {
      onSavingChanged?.call(false);
    }
  }

  Future<void> addLeg(BuildContext context) async {
    final result = await LegFormDialog.show(context);
    if (result == null || !context.mounted) return;
    await saveLegs(context, [...segment.legs.map(legToMap), result]);
  }

  Future<void> editLeg(BuildContext context, int index) async {
    final leg = segment.legs[index];
    final result = await LegFormDialog.show(context, existing: leg);
    if (result == null || !context.mounted) return;
    // LegFormDialog signals deletion via a sentinel map instead of a separate
    // return type so the Future<Map?> signature stays unchanged.
    if (result['__action'] == 'delete') {
      // A segment with zero legs is invalid — redirect the user to delete
      // the whole segment rather than leaving an empty shell.
      if (segment.legs.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.segmentNeedsOneLeg),
          ),
        );
        return;
      }
      await saveLegs(context, [
        for (var i = 0; i < segment.legs.length; i++)
          if (i != index) legToMap(segment.legs[i]),
      ]);
      return;
    }
    await saveLegs(context, [
      for (var i = 0; i < segment.legs.length; i++)
        i == index ? result : legToMap(segment.legs[i]),
    ]);
  }
}
