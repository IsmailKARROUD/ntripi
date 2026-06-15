// features/profile/presentation/fullscreen_locations_map_screen.dart
//
// Interactive map of every stop coordinate the viewer can see for a user.
// Reached by tapping the profile hero map. Markers are colored by place_type;
// one polyline per source itinerary (joining stops across trips would be a lie).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
import 'package:social_flutter/features/profile/providers/user_locations_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class FullscreenLocationsMapScreen extends ConsumerWidget {
  final String userId;
  final String userName;

  const FullscreenLocationsMapScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  Color _colorFor(String? placeType) {
    final pt = PlaceType.fromString(placeType);
    if (pt == null) return kCanopy;
    return switch (pt) {
      PlaceType.eatDrink => const Color(0xFFE07A1F),
      PlaceType.sleep => const Color(0xFF3D6FB8),
      PlaceType.pray => const Color(0xFF8B6FB8),
      PlaceType.learnSee => const Color(0xFF1F8FA8),
      PlaceType.buy => const Color(0xFFB8377F),
      PlaceType.playWatch => const Color(0xFFB89B1F),
      PlaceType.nature => kCanopy,
      PlaceType.travel => const Color(0xFF6B7A5C),
      PlaceType.healBathe => const Color(0xFF1FB8A8),
      PlaceType.entertainment => const Color(0xFFB81F4B),
      PlaceType.sight => kForest,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final locationsAsync = ref.watch(userLocationsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(userName),
        backgroundColor: kSurface,
        foregroundColor: kBark,
        elevation: 0,
      ),
      body: locationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.couldNotLoadItineraries,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kText2),
            ),
          ),
        ),
        data: (locations) {
          if (locations.isEmpty) {
            return Center(
              child: Text(
                l10n.noStopsYet,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kText2,
                ),
              ),
            );
          }

          final points =
              locations.map((l) => LatLng(l.lat, l.lng)).toList();

          // Group locations by itinerary in insertion order so each trip gets
          // its own polyline. Joining stops across trips would be a lie.
          final byItinerary = <String, List<VisitedLocation>>{};
          for (final loc in locations) {
            byItinerary.putIfAbsent(loc.itineraryId, () => []).add(loc);
          }

          return FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(40),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.ntripi',
              ),
              for (final group in byItinerary.values)
                if (group.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: group
                            .map((l) => LatLng(l.lat, l.lng))
                            .toList(),
                        color: kCanopy.withValues(alpha: 0.55),
                        strokeWidth: 2.5,
                      ),
                    ],
                  ),
              MarkerLayer(
                markers: locations
                    .map((loc) => Marker(
                          point: LatLng(loc.lat, loc.lng),
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _colorFor(loc.placeType),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(Icons.place,
                                color: Colors.white, size: 10),
                          ),
                        ))
                    .toList(),
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(l10n.openStreetMapContributors),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
