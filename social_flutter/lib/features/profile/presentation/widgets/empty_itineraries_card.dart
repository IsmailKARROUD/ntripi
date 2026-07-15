import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class EmptyItinerariesCard extends StatelessWidget {
  final VoidCallback onCreateTap;
  final VoidCallback onExploreTap;

  const EmptyItinerariesCard({
    super.key,
    required this.onCreateTap,
    required this.onExploreTap,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: nt.mist,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: nt.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: nt.forest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: nt.forest.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(Icons.map_rounded,
                    color: Theme.of(context).colorScheme.onPrimary, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.planFirstJourney,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: nt.bark,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.planFirstJourneyHint,
                style: TextStyle(
                    fontSize: 13, color: nt.text2, height: 1.5),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onCreateTap,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: nt.forest,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: nt.forest.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 18),
                      const SizedBox(width: 6),
                      Text(
                        l10n.createItinerary,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onExploreTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: nt.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: nt.border),
            ),
            child: Row(
              children: [
                const _SmallIconBox(icon: Icons.explore_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.needInspiration,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: nt.bark,
                        ),
                      ),
                      Text(
                        l10n.browseForIdeas,
                        style:
                            TextStyle(fontSize: 11, color: nt.text2),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: nt.text3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SmallIconBox extends StatelessWidget {
  final IconData icon;
  const _SmallIconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: nt.sand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: nt.forest),
    );
  }
}
