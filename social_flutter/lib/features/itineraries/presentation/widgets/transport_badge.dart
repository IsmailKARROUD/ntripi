// widgets/transport_badge.dart — Compact chip for one transport leg inside a SegmentCard.
//
// Displays: mode icon · leg summary · per-leg cost · per-leg duration.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/services/currency.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class TransportBadge extends StatelessWidget {
  final TransportLeg leg;
  final String currency;

  const TransportBadge(
      {super.key, required this.leg, required this.currency});

  // Returns null when the leg has no cost info at all (cost == 0 and not free),
  // so the badge doesn't show a misleading "0.00" or empty label.
  String? _costLabel(AppLocalizations l10n) {
    if (leg.isFree) return l10n.freeLegLabel;
    if (leg.cost > 0) return formatMoney(leg.cost, currency);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final costLabel = _costLabel(l10n);
    String _legString = leg.summary(l10n);
    if (costLabel != null) {
      _legString += ' · $costLabel';
    }
    final dur = leg.formattedDuration(l10n);
    if (dur.isNotEmpty) {
      _legString += ' · $dur';
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
  final String? label;
  const AddTransportBadge({super.key, this.label});

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
            label ?? AppLocalizations.of(context)!.addTransitTitle,
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
