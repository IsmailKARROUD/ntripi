// widgets/route_start_sheet.dart — Asks where the trip's Google Maps route
// starts: the device location (directions to go now) or the first stop (the
// trip alone). Asked every time — the right start depends on the moment.
//
// Returns the choice and launches nothing: the trip screen opens the route, so
// the sheet needs no provider and a dismissal simply opens nothing.

import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/maps_launcher_service.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

Future<RouteStart?> showRouteStartSheet(BuildContext context) {
  return showModalBottomSheet<RouteStart>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _RouteStartSheet(),
  );
}

class _RouteStartSheet extends StatelessWidget {
  const _RouteStartSheet();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    // useSafeArea leaves the bottom inset to the content — the home indicator.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
              child: Text(
                l10n.openRouteInMaps,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: nt.bark,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            // Scrollable: at the largest text sizes the two answers outgrow a
            // small phone, and the second one was cut off beyond the screen.
            Flexible(
              child: SingleChildScrollView(
                child: SectionCard(
                  clipBehavior: Clip.antiAlias,
                  children: [
                    EditorialRow(
                      icon: Icons.my_location_rounded,
                      iconBg: nt.mist,
                      iconColor: nt.forest,
                      label: l10n.routeFromMyLocation,
                      subtitle: l10n.routeFromMyLocationHint,
                      onTap: () =>
                          Navigator.of(context).pop(RouteStart.myLocation),
                    ),
                    EditorialRow(
                      icon: Icons.trip_origin_rounded,
                      iconBg: nt.mist,
                      iconColor: nt.forest,
                      label: l10n.routeFromFirstStop,
                      subtitle: l10n.routeFromFirstStopHint,
                      isLast: true,
                      onTap: () =>
                          Navigator.of(context).pop(RouteStart.firstStop),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
