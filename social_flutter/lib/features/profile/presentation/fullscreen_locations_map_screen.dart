// features/profile/presentation/fullscreen_locations_map_screen.dart
//
// Interactive map of every stop coordinate the viewer can see for a user.
// Reached by tapping the profile hero map. All markers share one color and
// icon — this is the "where I've been" aggregate, not a per-trip detail,
// so distinguishing place types here would suggest meaning that isn't there.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
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

          return FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(40),
                // Guard against zero-size bounds (single / all-identical points):
                // an uncapped fit computes zoom=Infinity -> NaN camera -> hang.
                maxZoom: 16,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.ntripi',
              ),
              MarkerLayer(
                markers: locations
                    .map((loc) => Marker(
                          point: LatLng(loc.lat, loc.lng),
                          width: 20,
                          height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              color: kForest,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(Icons.place,
                                color: Colors.white, size: 9),
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
