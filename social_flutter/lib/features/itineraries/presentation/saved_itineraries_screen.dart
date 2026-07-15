// presentation/saved_itineraries_screen.dart — The "Saved" tab: itineraries the
// user has bookmarked, newest first. A client-side search bar appears once the
// list exceeds 10 items. Rides the Dio/Hive cache so it works offline.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

/// Below this count the list is short enough to scan without a search bar.
const _kSearchThreshold = 10;

class SavedItinerariesScreen extends ConsumerStatefulWidget {
  const SavedItinerariesScreen({super.key});

  @override
  ConsumerState<SavedItinerariesScreen> createState() =>
      _SavedItinerariesScreenState();
}

class _SavedItinerariesScreenState
    extends ConsumerState<SavedItinerariesScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Itinerary> _filter(List<Itinerary> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((i) => i.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final savedAsync = ref.watch(savedItinerariesProvider);

    return Scaffold(
      backgroundColor: nt.surface,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
            ),
            child: savedAsync.when(
              loading: () => const Center(child: NTripiItineraryLoader()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      extractErrorMessage(error as dynamic, l10n),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.read(savedItinerariesProvider.notifier).refresh(),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              data: (items) => _buildList(context, nt, l10n, items),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    NtripiColors nt,
    AppLocalizations l10n,
    List<Itinerary> items,
  ) {
    final filtered = _filter(items);
    // Threshold uses the full list length, not the filtered length, so the bar
    // doesn't disappear the moment a query narrows the results below 10.
    final showSearch = items.length > _kSearchThreshold;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(savedItinerariesProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
              child: Text(
                l10n.savedItinerariesTitle,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: nt.bark,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          if (showSearch)
            SliverToBoxAdapter(
              child: _SavedSearchBar(
                controller: _controller,
                onChanged: (q) => setState(() => _query = q),
                onClear: () {
                  _controller.clear();
                  setState(() => _query = '');
                },
              ),
            ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                nt: nt,
                message: items.isEmpty
                    ? l10n.noSavedItinerariesYet
                    : l10n.savedSearchNoResults,
                icon: items.isEmpty
                    ? Icons.bookmark_border
                    : Icons.search_off_rounded,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ItinerarySummaryCard(
                    key: ValueKey(filtered[index].id),
                    itinerary: filtered[index],
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NtripiColors nt;
  final String message;
  final IconData icon;

  const _EmptyState({
    required this.nt,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: nt.text3),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: nt.text2, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SavedSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: nt.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: nt.border),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
              child: Icon(Icons.search, size: 20, color: nt.text3),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.searchSavedHint,
                  hintStyle: TextStyle(
                    color: nt.text3,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: nt.bark,
                ),
                onChanged: onChanged,
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: nt.text2,
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
