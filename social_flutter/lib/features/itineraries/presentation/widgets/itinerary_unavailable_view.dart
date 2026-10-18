// features/itineraries/presentation/widgets/itinerary_unavailable_view.dart
//
// The two answers a trip that cannot be shown gets — mostly reached from a
// shared link, which is how people arrive at trips that are not theirs.
//
// Exactly two, and neither says why. The server answers one 403 for every
// "you may not see it" (followers only, specific people, only me, a moderator
// hide, a suspended owner, a block in either direction), so a blocked person
// reads the same words as anyone the trip was not shared with — wording that
// hinted at a block would give away what that single 403 protects.

import 'package:flutter/material.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_error_codes.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/unavailable_view.dart';

enum ItineraryUnavailable {
  /// It exists, and its owner has not shared it with you.
  noAccess,

  /// Deleted, never existed, or the link was cut short.
  notAvailable,
}

/// Which of the two a failed load is — or null for a failure worth retrying
/// (offline, a server error), which keeps the message and Retry.
ItineraryUnavailable? itineraryUnavailableFrom(Object error) {
  if (apiErrorCode(error) == 'itinerary_access_denied') {
    return ItineraryUnavailable.noAccess;
  }
  if (isGoneError(error)) return ItineraryUnavailable.notAvailable;
  return null;
}

class ItineraryUnavailableView extends StatelessWidget {
  final ItineraryUnavailable reason;

  /// The screen's way out, or null while edit mode owns Back (PopScope).
  final VoidCallback? onBack;

  const ItineraryUnavailableView({
    super.key,
    required this.reason,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (reason) {
      ItineraryUnavailable.noAccess => UnavailableView(
          icon: Icons.lock_outline,
          title: l10n.itineraryNoAccessTitle,
          message: l10n.itineraryNoAccessMessage,
          onBack: onBack,
        ),
      ItineraryUnavailable.notAvailable => UnavailableView(
          icon: Icons.wrong_location_outlined,
          title: l10n.itineraryUnavailableTitle,
          message: l10n.itineraryUnavailableMessage,
          onBack: onBack,
        ),
    };
  }
}
