// shared/widgets/location_error.dart — snackbar for failed device-location
// requests, shared by the map picker and the stop form's preview map.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/services/location_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Shows a localized snackbar for a non-success [LocationOutcome].
///
/// Permission/service failures get an action that opens the relevant OS
/// settings page so the user can fix the problem. No-op on [LocationSuccess].
void showLocationOutcomeSnackbar(
  BuildContext context,
  WidgetRef ref,
  LocationOutcome outcome,
) {
  final l10n = AppLocalizations.of(context)!;
  final service = ref.read(locationServiceProvider);
  switch (outcome) {
    case LocationSuccess():
      return;
    case LocationServiceDisabled():
      _show(
        context,
        l10n.locationServiceDisabled,
        settingsLabel: l10n.locationOpenSettings,
        onOpenSettings: service.openLocationSettings,
      );
    case LocationPermissionDenied():
      _show(
        context,
        l10n.locationPermissionDenied,
        settingsLabel: l10n.locationOpenSettings,
        onOpenSettings: service.openAppSettings,
      );
    case LocationUnavailable():
      _show(context, l10n.locationUnavailable);
  }
}

void _show(
  BuildContext context,
  String message, {
  String? settingsLabel,
  VoidCallback? onOpenSettings,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action:
            onOpenSettings == null
                ? null
                : SnackBarAction(
                  label: settingsLabel!,
                  onPressed: onOpenSettings,
                ),
      ),
    );
}
