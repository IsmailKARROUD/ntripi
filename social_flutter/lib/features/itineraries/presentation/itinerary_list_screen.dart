// presentation/itinerary_list_screen.dart — Shows the current user's itineraries.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/itinerary_summary_card.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';

class ItineraryListScreen extends ConsumerWidget {
  const ItineraryListScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Itinerary itinerary,
  ) async {
    final confirmed = await confirmTypedDestructiveAction(
      context: context,
      title: 'Delete this itinerary?',
      message: 'All stops, annotations, segments, ratings, and shared links '
          'will be permanently destroyed. This cannot be undone.',
      requiredText: itinerary.title,
      confirmLabel: 'Delete itinerary',
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
        SnackBar(content: Text(extractErrorMessage(e as dynamic))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itinerariesAsync = ref.watch(myItinerariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Itineraries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(myItinerariesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: itinerariesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                extractErrorMessage(error as dynamic),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.read(myItinerariesProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (itineraries) => RefreshIndicator(
          onRefresh: () =>
              ref.read(myItinerariesProvider.notifier).refresh(),
          child: itineraries.isEmpty
              ? ListView(
                  // physics that allow pull-to-refresh even when empty
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'No itineraries yet.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text('Tap + to create your first trip.'),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: itineraries.length,
                  itemBuilder: (context, index) {
                    final itinerary = itineraries[index];
                    return ItinerarySummaryCard(
                      itinerary: itinerary,
                      onLongPress: () =>
                          _confirmDelete(context, ref, itinerary),
                    );
                  },
                ),
        ),
      ),),),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/itineraries/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
