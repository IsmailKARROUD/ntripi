// features/profile/providers/user_locations_provider.dart
//
// Aggregate visited-stop coordinates for a user. Fed by the profile hero
// (when the user has no cover image) and the fullscreen "Where I've been"
// map. Result is cached per-user-ID for the session (Riverpod in-memory).
// Cross-session caching happens at the HTTP layer via ETag/304.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/features/profile/domain/visited_location.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';

class UserLocationsNotifier extends AsyncNotifier<List<VisitedLocation>> {
  UserLocationsNotifier(this.arg); // family argument: user id
  final String arg;

  @override
  Future<List<VisitedLocation>> build() async {
    return ref.read(profileRepositoryProvider).getUserLocations(arg);
  }

  Future<void> refresh() async {
    final userId = arg;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getUserLocations(userId),
    );
  }
}

final userLocationsProvider = AsyncNotifierProvider.family<
    UserLocationsNotifier, List<VisitedLocation>, String>(
  UserLocationsNotifier.new,
);
