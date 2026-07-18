// shared/widgets/device_location_dot.dart — blue "you are here" map marker.
//
// Shared by the stop-form preview map and the map picker so the device
// location renders identically everywhere. Display-only: the dot never
// participates in location selection.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

class DeviceLocationDot extends StatelessWidget {
  const DeviceLocationDot({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // light-palette blue — OSM tiles stay light in dark mode
        color: NtripiColors.light.editBlue,
        shape: BoxShape.circle,
        border: Border.all(color: NtripiBrand.chrome, width: 2.5),
        boxShadow: [
          BoxShadow(
            blurRadius: 6,
            color: NtripiBrand.backdrop.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}
