// presentation/itinerary_list_screen.dart — Shows the current user's itineraries.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';

class ItineraryListScreen extends ConsumerWidget {
  const ItineraryListScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Itinerary itinerary,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete itinerary?'),
        content: Text(
          '"${itinerary.title}" and all its stops will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

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
      body: itinerariesAsync.when(
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
        data: (itineraries) {
          if (itineraries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No itineraries yet.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first trip.'),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(myItinerariesProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: itineraries.length,
              itemBuilder: (context, index) {
                final itinerary = itineraries[index];
                return _ItineraryCard(
                  itinerary: itinerary,
                  onTap: () => context.push('/itineraries/${itinerary.id}'),
                  onLongPress: () =>
                      _confirmDelete(context, ref, itinerary),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/itineraries/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ItineraryCard({
    required this.itinerary,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + visibility badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      itinerary.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: itinerary.isPublic
                          ? Colors.green.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: itinerary.isPublic
                            ? Colors.green.shade200
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      itinerary.isPublic ? 'Public' : 'Private',
                      style: TextStyle(
                        fontSize: 11,
                        color: itinerary.isPublic
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Stats row
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _Stat(
                    icon: Icons.timer_outlined,
                    label: itinerary.formattedDuration,
                  ),
                  _Stat(
                    icon: Icons.payments_outlined,
                    label: itinerary.formattedCost,
                  ),
                  _Stat(
                    icon: Icons.place_outlined,
                    label:
                        '${itinerary.stops.length} stop${itinerary.stops.length == 1 ? '' : 's'}',
                  ),
                  if (itinerary.safetyRating != null)
                    _Stat(
                      icon: Icons.star,
                      label: '${itinerary.safetyRating}/5',
                      iconColor: Colors.amber,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const _Stat({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
      ],
    );
  }
}
