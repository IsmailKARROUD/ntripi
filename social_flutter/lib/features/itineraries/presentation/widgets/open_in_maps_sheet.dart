// widgets/open_in_maps_sheet.dart — Bottom-sheet picker to open a location in
// an external map app. Lists only the apps detected on the device.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/data/maps_launcher_service.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Future<void> showOpenInMapsSheet({
  required BuildContext context,
  required double lat,
  required double lng,
  String? label,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OpenInMapsSheet(lat: lat, lng: lng, label: label),
  );
}

class _OpenInMapsSheet extends ConsumerStatefulWidget {
  final double lat;
  final double lng;
  final String? label;

  const _OpenInMapsSheet({required this.lat, required this.lng, this.label});

  @override
  ConsumerState<_OpenInMapsSheet> createState() => _OpenInMapsSheetState();
}

class _OpenInMapsSheetState extends ConsumerState<_OpenInMapsSheet> {
  // Resolved once in initState — a rebuilt FutureBuilder future would re-probe
  // the platform channel on every frame.
  late final Future<List<ExternalMapApp>> _apps;

  @override
  void initState() {
    super.initState();
    _apps = ref.read(mapsLauncherServiceProvider).installedApps();
  }

  // Brand names are proper nouns — deliberately not localized. The geo:
  // chooser is the one exception (see _appName).
  static const _appNames = {
    ExternalMapApp.googleMaps: 'Google Maps',
    ExternalMapApp.appleMaps: 'Apple Maps',
    ExternalMapApp.waze: 'Waze',
    ExternalMapApp.hereWeGo: 'HERE WeGo',
    ExternalMapApp.yandexMaps: 'Yandex Maps',
    ExternalMapApp.citymapper: 'Citymapper',
    ExternalMapApp.osmAnd: 'OsmAnd',
    ExternalMapApp.openStreetMap: 'OpenStreetMap',
  };

  String _appName(AppLocalizations l10n, ExternalMapApp app) =>
      _appNames[app] ?? l10n.otherMapsApp;

  // Brand marks come from FontAwesome; the rest fall back to Material glyphs.
  Widget _appIcon(ExternalMapApp app) {
    switch (app) {
      case ExternalMapApp.googleMaps:
        return const FaIcon(FontAwesomeIcons.google, size: 18, color: kForest);
      case ExternalMapApp.appleMaps:
        return const FaIcon(FontAwesomeIcons.apple, size: 18, color: kForest);
      case ExternalMapApp.waze:
        return const FaIcon(FontAwesomeIcons.waze, size: 18, color: kForest);
      case ExternalMapApp.yandexMaps:
        return const FaIcon(FontAwesomeIcons.yandex, size: 18, color: kForest);
      case ExternalMapApp.hereWeGo:
        return const Icon(Icons.explore_rounded, size: 20, color: kForest);
      case ExternalMapApp.citymapper:
        return const Icon(Icons.directions_transit_rounded,
            size: 20, color: kForest);
      case ExternalMapApp.osmAnd:
        return const Icon(Icons.terrain_rounded, size: 20, color: kForest);
      case ExternalMapApp.openStreetMap:
        return const Icon(Icons.public_rounded, size: 20, color: kForest);
      case ExternalMapApp.otherApps:
        return const Icon(Icons.pin_drop_rounded, size: 20, color: kForest);
    }
  }

  void _open(ExternalMapApp app) {
    ref.read(mapsLauncherServiceProvider).openPlace(
          app,
          lat: widget.lat,
          lng: widget.lng,
          label: widget.label,
        );
    Navigator.of(context).pop();
  }

  Widget _buildAppRow(AppLocalizations l10n, ExternalMapApp app) {
    return InkWell(
      onTap: () => _open(app),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kMist,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: _appIcon(app),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _appName(l10n, app),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: kText3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: kSand,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section label
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Text(
                  l10n.openInMaps.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              // App rows in a white card
              Container(
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: FutureBuilder<List<ExternalMapApp>>(
                  future: _apps,
                  builder: (context, snap) {
                    final apps = snap.data;
                    if (apps == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: kForest),
                          ),
                        ),
                      );
                    }
                    // Cap the height so a long list (up to 8 apps) scrolls
                    // instead of overflowing on short screens.
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < apps.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _buildAppRow(l10n, apps[i]),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
