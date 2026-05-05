// widgets/transport_badge.dart — Compact badge: mode · line/direction · duration · cost.
// When the leg has a noteType the badge adopts the annotation colour palette.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

const _noteTypeConfigs = {
  AnnotationType.advice: (
    bg: kMist,
    fg: kForest,
    icon: Icons.lightbulb_outline,
  ),
  AnnotationType.caution: (
    bg: Color(0xFFFFF0CC),
    fg: kAmber,
    icon: Icons.warning_amber_outlined,
  ),
  AnnotationType.avoid: (
    bg: Color(0xFFFFDAD6),
    fg: Color(0xFFBA1A1A),
    icon: Icons.block,
  ),
  AnnotationType.info: (
    bg: Color(0xFFD0EDD8),
    fg: kCanopy,
    icon: Icons.info_outline,
  ),
};

class TransportBadge extends StatelessWidget {
  final TransportLeg leg;
  /// Currency code shown after the cost amount (e.g. "EUR"). Omit to hide cost.
  final String? currency;

  const TransportBadge({super.key, required this.leg, this.currency});

  String get _label {
    final parts = <String>[leg.summary];
    if (leg.durationMin != null && leg.durationMin! > 0) {
      final h = leg.durationMin! ~/ 60;
      final m = leg.durationMin! % 60;
      parts.add(h == 0 ? '${m}min' : (m == 0 ? '${h}h' : '${h}h ${m}min'));
    }
    if (currency != null) {
      if (leg.isFree) {
        parts.add('Free');
      } else if (leg.cost > 0) {
        parts.add('${leg.cost.toStringAsFixed(2)} $currency');
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final config = leg.noteType != null ? _noteTypeConfigs[leg.noteType!] : null;
    final bg = config?.bg ?? Colors.grey.shade200;
    final fg = config?.fg ?? Colors.grey.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(leg.mode.icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
