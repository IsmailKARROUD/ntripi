// widgets/transport_badge.dart — Compact chip for one transport leg inside a SegmentCard.
//
// Displays: mode icon · leg summary · per-leg cost · segment total duration.
// formattedDuration is the segment-level total, not per-leg — it's shown once
// per badge because the badge is the only visible unit in the card's Wrap.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

class TransportBadge extends StatelessWidget {
  final TransportLeg leg;
  final String currency;
  // Segment-level total duration passed in from SegmentCard — not a per-leg value.
  final String formattedDuration;

  const TransportBadge(
      {super.key,
      required this.leg,
      required this.currency,
      required this.formattedDuration});

  // Returns null when the leg has no cost info at all (cost == 0 and not free),
  // so the badge doesn't show a misleading "0.00" or empty label.
  String? get _costLabel {
    if (leg.isFree) return 'Free';
    if (leg.cost > 0) return '${leg.cost.toStringAsFixed(2)} $currency';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final costLabel = _costLabel;
    String _legString = leg.summary;
    if (costLabel != null) {
      _legString += ' · $costLabel';
    }
    if (formattedDuration.isNotEmpty && formattedDuration != '—') {
      _legString += ' · $formattedDuration';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kSand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(leg.mode.icon, size: 13, color: kCanopy),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _legString,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: kCanopy,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class AddTransportBadge extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  final String label;
  const AddTransportBadge({super.key, this.label = 'Add transit'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kSand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add, size: 13, color: kCanopy),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: kCanopy),
          ),
        ],
      ),
    );
  }
}
