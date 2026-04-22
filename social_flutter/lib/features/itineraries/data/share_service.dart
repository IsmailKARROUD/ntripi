// data/share_service.dart — Builds a share caption and invokes the OS share sheet.

import 'package:share_plus/share_plus.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';

class ShareService {
  /// Opens the native OS share sheet with the itinerary landing page URL.
  Future<void> shareItinerary(Itinerary itinerary) async {
    final url = shareUrlFor(itinerary.id);
    final caption = _buildCaption(itinerary);
    await Share.share('$caption\n$url', subject: itinerary.title);
  }

  String _buildCaption(Itinerary itinerary) {
    final stopCount = itinerary.stops.length;
    final stopLabel = stopCount == 1 ? '1 stop' : '$stopCount stops';
    return 'Check out "${itinerary.title}" on Ntripi — $stopLabel, ${itinerary.formattedDuration}';
  }
}
