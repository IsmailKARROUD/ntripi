// presentation/itinerary_list_screen.dart — Shows the current user's itineraries.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class ItineraryListScreen extends ConsumerWidget {
  const ItineraryListScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Itinerary itinerary,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmTypedDestructiveAction(
      context: context,
      title: l10n.deleteItineraryTitle,
      message: l10n.deleteItineraryMessage,
      requiredText: itinerary.title,
      confirmLabel: l10n.deleteItineraryButton,
      hintText: itinerary.title,
    );

    if (!confirmed || !context.mounted) return;

    try {
      await ref
          .read(myItinerariesProvider.notifier)
          .removeItinerary(itinerary.id);
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final itinerariesAsync = ref.watch(myItinerariesProvider);

    return Scaffold(
      backgroundColor: kSand,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
            ),
            child: itinerariesAsync.when(
              loading: () =>
                  const Center(child: NTripiItineraryLoader()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      extractErrorMessage(error as dynamic, AppLocalizations.of(context)!),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.read(myItinerariesProvider.notifier).refresh(),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              data: (itineraries) => RefreshIndicator(
                onRefresh: () async {
                  // Evict CachedNetworkImage entries so a pull-to-refresh
                  // shows updated cover images replaced from another device.
                  await Future.wait([
                    for (final it in itineraries)
                      if (it.coverImageUrl != null)
                        CachedNetworkImage.evictFromCache(
                          it.coverImageUrl!.startsWith('/')
                              ? '$kApiBaseUrl${it.coverImageUrl}'
                              : it.coverImageUrl!,
                          cacheManager: NtripiImageCacheManager(),
                        ),
                  ]);
                  await ref
                      .read(myItinerariesProvider.notifier)
                      .refresh();
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    // Title row
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.myItineraries,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: kBark,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Summary pills
                    if (itineraries.isNotEmpty) ...[
                      _SummaryPillsRow(itineraries: itineraries),
                      const SizedBox(height: 12),
                    ],

                    // Empty state
                    if (itineraries.isEmpty)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.55,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.map_outlined,
                                size: 64, color: kText3),
                            const SizedBox(height: 16),
                            Text(
                              l10n.noItinerariesYet,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(l10n.tapToCreateFirst,
                                style: const TextStyle(color: kText2)),
                          ],
                        ),
                      ),

                    // Card list
                    for (final itinerary in itineraries)
                      ItinerarySummaryCard(
                        key: ValueKey(itinerary.id),
                        itinerary: itinerary,
                        onLongPress: () =>
                            _confirmDelete(context, ref, itinerary),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/itineraries/new'),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.newItinerary),
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// Row of three summary pills — trips / stops / travelled.
class _SummaryPillsRow extends StatelessWidget {
  final List<Itinerary> itineraries;

  const _SummaryPillsRow({required this.itineraries});

  String _totalTravelled() {
    final totalMin =
        itineraries.fold(0, (sum, it) => sum + it.totalDurationMin);
    if (totalMin <= 0) return '—';
    final days = totalMin ~/ (60 * 24);
    if (days >= 1) return '${days}d';
    final hours = totalMin ~/ 60;
    return '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    final totalStops = itineraries.fold(0, (sum, it) => sum + it.stopsCount);
    return Row(
      children: [
        _SummaryPill(
          icon: Icons.route_rounded,
          value: '${itineraries.length}',
          label: 'trips',
        ),
        const SizedBox(width: 8),
        _SummaryPill(
          icon: Icons.location_on_rounded,
          value: '$totalStops',
          label: 'stops',
        ),
        const SizedBox(width: 8),
        _SummaryPill(
          icon: Icons.schedule_rounded,
          value: _totalTravelled(),
          label: 'travelled',
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _SummaryPill({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: kForest),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kBark,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: kText2,
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
