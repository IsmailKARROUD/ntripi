// presentation/itinerary_list_screen.dart — the current user's itineraries:
// the ones they own, plus the ones they were granted edit rights on, behind an
// All / Mine / Shared segmented control.
//
// The two groups come from two endpoints and stay two providers, because they
// answer different questions and fail independently. A row's PROVENANCE is what
// decides the owner-only chrome: /itineraries/me is owner-only by construction,
// so a null owner here is a stronger signal than comparing ids, and it needs no
// profile load.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/services/sfx_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/shared_itinerary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

/// One row in the merged list. [owner] is null exactly when the viewer owns the
/// trip, which is what gates the delete gesture and the card type.
class _Row {
  final Itinerary itinerary;
  final FeedOwner? owner;

  const _Row(this.itinerary, [this.owner]);

  bool get isOwned => owner == null;
}

class ItineraryListScreen extends ConsumerStatefulWidget {
  const ItineraryListScreen({super.key});

  @override
  ConsumerState<ItineraryListScreen> createState() =>
      _ItineraryListScreenState();
}

class _ItineraryListScreenState extends ConsumerState<ItineraryListScreen> {
  // Blocks the screen with the SavingOverlay loader while a delete is in
  // flight — removeItinerary awaits the network call before dropping the card.
  bool _deleting = false;

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

    final sfx = ref.read(sfxServiceProvider); // read before the await
    setState(() => _deleting = true);
    try {
      await ref
          .read(myItinerariesProvider.notifier)
          .removeItinerary(itinerary.id);
      // After the network call, never on confirm — a failed delete must not
      // sound like a successful one.
      unawaited(sfx.play(Sfx.deleteItinerary));
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractErrorMessage(e as dynamic, AppLocalizations.of(context)!))),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Refreshes whichever lists the active scope actually shows.
  Future<void> _refresh(ItineraryScope scope) async {
    await Future.wait([
      if (scope != ItineraryScope.shared)
        ref.read(myItinerariesProvider.notifier).refresh(),
      if (scope != ItineraryScope.mine)
        ref.read(sharedWithMeProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final scope = ref.watch(itineraryScopeProvider);
    final mineAsync = ref.watch(myItinerariesProvider);
    final sharedAsync = ref.watch(sharedWithMeProvider);
    // Long-press delete is a hidden gesture with no visual to grey out —
    // offline it just no-ops; the shell's offline banner explains why.
    final online = ref.watch(isOnlineProvider).value ?? true;

    // Only the lists this scope renders may block or break it: a dead
    // shared-with-me call must never take the Mine segment down with it.
    final needed = <AsyncValue<Object>>[
      if (scope != ItineraryScope.shared) mineAsync,
      if (scope != ItineraryScope.mine) sharedAsync,
    ];
    final loading = needed.any((a) => a.isLoading && !a.hasValue);
    final failure = needed.where((a) => a.hasError && !a.hasValue).firstOrNull;

    final rows = <_Row>[
      if (scope != ItineraryScope.shared)
        for (final it in mineAsync.value ?? const <Itinerary>[]) _Row(it),
      if (scope != ItineraryScope.mine)
        for (final item in sharedAsync.value ?? const <FeedItem>[])
          _Row(item.itinerary, item.owner),
    ]..sort((a, b) => b.itinerary.createdAt.compareTo(a.itinerary.createdAt));

    return SavingOverlay(
      saving: _deleting,
      tint: nt.surface,
      child: Scaffold(
      backgroundColor: nt.surface,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
            ),
            child: RefreshIndicator(
                onRefresh: () async {
                  // Offline: skip entirely — evicting covers would delete
                  // images the device can't re-download.
                  if (!isOnlineNow(ref)) return;
                  // Evict CachedNetworkImage entries so a pull-to-refresh
                  // shows updated cover images replaced from another device.
                  await Future.wait([
                    for (final row in rows)
                      if (row.itinerary.coverImageUrl != null)
                        CachedNetworkImage.evictFromCache(
                          row.itinerary.coverImageUrl!.startsWith('/')
                              ? '$kApiBaseUrl${row.itinerary.coverImageUrl}'
                              : row.itinerary.coverImageUrl!,
                          cacheManager: NtripiImageCacheManager(),
                        ),
                  ]);
                  await _refresh(scope);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    // Title row — names the tab, not the active scope.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.myItineraries,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: nt.bark,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scope filter — its own full-width row rather than beside
                    // the title: three labels in German or Arabic will not fit
                    // next to a 22px heading on a narrow phone.
                    _ScopeSelector(scope: scope),
                    const SizedBox(height: 12),

                    // Loading and error live BELOW the selector, inside the
                    // list, rather than replacing the whole screen: a dead
                    // shared-with-me call otherwise takes the control away with
                    // it and strands the user on a scope they cannot leave.
                    if (loading)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: const Center(child: NTripiItineraryLoader()),
                      )
                    else if (failure != null)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              extractErrorMessage(
                                  failure.error as dynamic, l10n),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => _refresh(scope),
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      ),

                    // Summary pills — total whatever is on screen, so the
                    // numbers always agree with the cards under them.
                    if (!loading && failure == null && rows.isNotEmpty) ...[
                      _SummaryPillsRow(
                        itineraries: [for (final r in rows) r.itinerary],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Empty state
                    if (!loading && failure == null && rows.isEmpty)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.55,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              scope == ItineraryScope.shared
                                  ? Icons.group_outlined
                                  : Icons.map_outlined,
                              size: 64,
                              color: nt.text3,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              scope == ItineraryScope.shared
                                  ? l10n.sharedItinerariesEmpty
                                  : l10n.noItinerariesYet,
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                scope == ItineraryScope.shared
                                    ? l10n.sharedItinerariesEmptyHint
                                    : l10n.tapToCreateFirst,
                                style: TextStyle(color: nt.text2),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Card list — an editor never gets the owner's delete
                    // gesture, so the long-press is owned-rows only.
                    for (final row in rows)
                      row.isOwned
                          ? ItinerarySummaryCard(
                              key: ValueKey(row.itinerary.id),
                              itinerary: row.itinerary,
                              onLongPress: online
                                  ? () => _confirmDelete(
                                      context, ref, row.itinerary)
                                  : null,
                            )
                          : SharedItineraryCard(
                              key: ValueKey(row.itinerary.id),
                              item: FeedItem(
                                itinerary: row.itinerary,
                                owner: row.owner!,
                              ),
                            ),
                  ],
                ),
              ),
          ),
        ),
      ),
      floatingActionButton: OfflineGate(
        // FABs have no native disabled style — dim explicitly when offline.
        builder: (online) => Opacity(
          opacity: online ? 1 : 0.55,
          child: FloatingActionButton.extended(
            onPressed:
                online ? () => context.push('/itineraries/new') : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.newItinerary),
            backgroundColor: nt.forest,
            // onPrimary, not white — dark mode lightens the green fill
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    ),
    );
  }
}

// All / Mine / Shared. Labels only, no icons — three segments with icons
// overflow once the labels are translated.
class _ScopeSelector extends ConsumerWidget {
  final ItineraryScope scope;

  const _ScopeSelector({required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ItineraryScope>(
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          ButtonSegment(
            value: ItineraryScope.all,
            label: Text(l10n.itinerariesScopeAll),
          ),
          ButtonSegment(
            value: ItineraryScope.mine,
            label: Text(l10n.itinerariesScopeMine),
          ),
          ButtonSegment(
            value: ItineraryScope.shared,
            label: Text(l10n.itinerariesScopeShared),
          ),
        ],
        selected: {scope},
        showSelectedIcon: false,
        onSelectionChanged: (s) =>
            ref.read(itineraryScopeProvider.notifier).set(s.first),
      ),
    );
  }
}

// Row of three summary pills — trips / stops / travelled.
class _SummaryPillsRow extends StatelessWidget {
  final List<Itinerary> itineraries;

  const _SummaryPillsRow({required this.itineraries});

  String _totalTravelled(AppLocalizations l10n) {
    final totalMin =
        itineraries.fold(0, (sum, it) => sum + it.totalDurationMin);
    if (totalMin <= 0) return '—';
    final days = totalMin ~/ (60 * 24);
    if (days >= 1) return '$days${l10n.daysLabel}';
    final hours = totalMin ~/ 60;
    return '$hours${l10n.hoursLabel}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalStops = itineraries.fold(0, (sum, it) => sum + it.stopsCount);
    return Row(
      children: [
        _SummaryPill(
          icon: Icons.route_rounded,
          value: '${itineraries.length}',
          label: l10n.tripsPillLabel,
        ),
        const SizedBox(width: 8),
        _SummaryPill(
          icon: Icons.location_on_rounded,
          value: '$totalStops',
          label: l10n.stopsPillLabel,
        ),
        const SizedBox(width: 8),
        _SummaryPill(
          icon: Icons.schedule_rounded,
          value: _totalTravelled(l10n),
          label: l10n.travelledPillLabel,
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
    final nt = context.nt;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: nt.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: nt.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: nt.forest),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: nt.text2,
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
