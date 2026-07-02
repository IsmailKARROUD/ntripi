// data/share_service.dart — Builds a share caption and invokes the OS share sheet.

import 'package:share_plus/share_plus.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';

class ShareService {
  /// Opens the native OS share sheet with the itinerary landing page URL.
  Future<void> shareItinerary(Itinerary itinerary) async {
    final url = shareUrlFor(itinerary.id);
    final caption = _buildCaption(itinerary);
    // share_plus 13 replaced the top-level Share.share() with the instance API.
    await SharePlus.instance.share(
      ShareParams(text: '$caption\n$url', subject: itinerary.title),
    );
  }

  String _buildCaption(Itinerary itinerary) {
    // Summary itineraries (e.g. from the feed) carry no loaded tracks/stops, so
    // fall back to the denormalized stopsCount when the stop list is empty.
    final stopCount = itinerary.stops.isNotEmpty
        ? itinerary.stops.length
        : itinerary.stopsCount;
    final stopLabel = stopCount == 1 ? '1 stop' : '$stopCount stops';
    return 'Check out "${itinerary.title}" on Ntripi — $stopLabel, ${itinerary.formattedDuration}';
  }
}
