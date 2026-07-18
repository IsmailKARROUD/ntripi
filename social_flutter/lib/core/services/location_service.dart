// core/services/location_service.dart — device GPS position via geolocator.
//
// Used to center the stop-form preview map and the map picker on the user.
// The position is display-only ("you are here" dot / camera target) — it is
// never written into a stop's coordinates without an explicit user pick.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Result of a device-location request. Callers switch on the subtype to
/// decide between using the position and showing a localized error.
sealed class LocationOutcome {
  const LocationOutcome();
}

class LocationSuccess extends LocationOutcome {
  final LatLng position;
  const LocationSuccess(this.position);
}

/// OS-level location services (GPS toggle) are off.
class LocationServiceDisabled extends LocationOutcome {
  const LocationServiceDisabled();
}

/// User denied the permission prompt (or denied it permanently in settings).
class LocationPermissionDenied extends LocationOutcome {
  const LocationPermissionDenied();
}

/// Position fix failed for another reason (timeout, platform error).
class LocationUnavailable extends LocationOutcome {
  const LocationUnavailable();
}

class LocationService {
  /// Returns the current device position, requesting permission if needed.
  ///
  /// Never throws — all failures map to a [LocationOutcome] subtype so the
  /// UI can stay silent (stop form) or show a snackbar (map picker button).
  Future<LocationOutcome> getCurrentLatLng() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServiceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationPermissionDenied();
      }

      // Medium accuracy is plenty for centering a city-level map and is
      // faster/cheaper than a full GPS fix.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationSuccess(LatLng(position.latitude, position.longitude));
    } on Exception {
      return const LocationUnavailable();
    }
  }
}

/// Riverpod provider for the LocationService singleton.
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});
