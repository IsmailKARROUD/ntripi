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
  // A single shared in-flight fix. Rapid double-taps — or the recenter and
  // capture buttons firing in the same frame, before their disable-guard
  // rebuilds — would otherwise start overlapping platform requests, which
  // geolocator rejects, surfacing a spurious "couldn't get your location".
  Future<LocationOutcome>? _inFlight;

  /// Returns the current device position, requesting permission if needed.
  ///
  /// Never throws — all failures map to a [LocationOutcome] subtype so the
  /// UI can stay silent (stop form) or show a snackbar (map picker button).
  /// Concurrent callers share the one platform request held in [_inFlight].
  Future<LocationOutcome> getCurrentLatLng() {
    return _inFlight ??= _fetchPosition().whenComplete(() => _inFlight = null);
  }

  Future<LocationOutcome> _fetchPosition() async {
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
      // A fresh fix can still fail transiently (timeout, or an overlapping
      // request the OS rejected on a rapid re-tap) — fall back to the last
      // cached fix so a quick second tap resolves instead of erroring out.
      final cached = await _lastKnown();
      return cached != null
          ? LocationSuccess(cached)
          : const LocationUnavailable();
    }
  }

  Future<LatLng?> _lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null; // getLastKnownPosition is unsupported on web
    }
  }

  /// Opens the OS app-settings page so the user can grant a denied permission.
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Opens the OS location-settings page so the user can turn GPS back on.
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}

/// Riverpod provider for the LocationService singleton.
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});
