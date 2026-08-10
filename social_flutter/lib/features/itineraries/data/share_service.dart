// data/share_service.dart — Builds a share caption and invokes the OS share sheet.

import 'package:share_plus/share_plus.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

class ShareService {
  /// Opens the native OS share sheet with the itinerary landing page URL.
  Future<void> shareItinerary(Itinerary itinerary, AppLocalizations l10n) async {
    final url = shareUrlFor(itinerary.id);
    final caption = _buildCaption(itinerary, l10n);
    // share_plus 13 replaced the top-level Share.share() with the instance API.
    await SharePlus.instance.share(
      ShareParams(text: '$caption\n$url', subject: itinerary.title),
    );
  }

  /// Opens the native OS share sheet with the profile landing page URL.
  Future<void> shareProfile(User user, AppLocalizations l10n) async {
    final url = profileShareUrlFor(user.username);
    final caption = l10n.shareProfileCaption(user.nameForDisplay);
    await SharePlus.instance.share(
      ShareParams(text: '$caption\n$url', subject: user.nameForDisplay),
    );
  }

  String _buildCaption(Itinerary itinerary, AppLocalizations l10n) {
    // Summary itineraries (e.g. from the feed) carry no loaded tracks/stops, so
    // fall back to the denormalized stopsCount when the stop list is empty.
    final stopCount = itinerary.stops.isNotEmpty
        ? itinerary.stops.length
        : itinerary.stopsCount;
    return l10n.shareCaption(itinerary.title, l10n.stopCount(stopCount),
        itinerary.formattedDuration(l10n));
  }
}
