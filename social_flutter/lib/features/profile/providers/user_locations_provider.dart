// features/profile/providers/user_locations_provider.dart
//
// Aggregate visited-stop coordinates for a user. Fed by the profile hero
// (when the user has no cover image) and the fullscreen "Where I've been"
// map. Result is cached per-user-ID for the session (Riverpod in-memory).
// Cross-session caching happens at the HTTP layer via ETag/304.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/providers/reload_keeps_content.dart';
import 'package:ntripi/features/profile/domain/visited_location.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';

class UserLocationsNotifier extends AsyncNotifier<List<VisitedLocation>>
    with ReloadKeepsContent<List<VisitedLocation>> {
  UserLocationsNotifier(this.arg); // family argument: user id
  final String arg;

  @override
  Future<List<VisitedLocation>> build() async {
    return ref.read(profileRepositoryProvider).getUserLocations(arg);
  }

  /// Pull-to-refresh on the profile: the map stays on screen while it reloads.
  Future<ReloadFailure?> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return null;
    return reloadKeepingContent(
      () => ref
          .read(profileRepositoryProvider)
          .getUserLocations(arg, forceRefresh: true),
    );
  }
}

final userLocationsProvider = AsyncNotifierProvider.family<
    UserLocationsNotifier, List<VisitedLocation>, String>(
  UserLocationsNotifier.new,
);
