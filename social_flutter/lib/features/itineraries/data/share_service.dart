// data/share_service.dart — what a Share button hands out, and the ways to hand
// it out. The presentation half, which picks one per platform, is
// presentation/widgets/share_link_action.dart.

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/browser_share_io.dart'
    if (dart.library.js_interop) 'package:ntripi/features/itineraries/data/browser_share_web.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

/// A shared trip or profile: [url] alone is what Copy link copies; [text] is
/// what another app gets.
class ShareLink {
  const ShareLink({
    required this.url,
    required this.caption,
    required this.subject,
  });

  final String url;
  final String caption;
  final String subject;

  /// The caption, then the link on a line of its own.
  String get text => '$caption\n$url';
}

class ShareService {
  ShareService({MethodChannel channel = const MethodChannel('ntripi/share')})
      : _channel = channel;

  // The phones' own share popup with one row added — Copy link — which
  // share_plus cannot do: MainActivity.kt and AppDelegate.swift answer it.
  final MethodChannel _channel;

  ShareLink itineraryLink(Itinerary itinerary, AppLocalizations l10n) =>
      ShareLink(
        url: shareUrlFor(itinerary.id),
        caption: _buildCaption(itinerary, l10n),
        subject: itinerary.title,
      );

  ShareLink profileLink(User user, AppLocalizations l10n) => ShareLink(
        url: profileShareUrlFor(user.username),
        caption: l10n.shareProfileCaption(user.nameForDisplay),
        subject: user.nameForDisplay,
      );

  /// The phone's own share popup for [link], with one more row: [copyLinkLabel],
  /// which copies the link alone. True when the reader picked that row and the
  /// app should say so — iOS reports it; Android confirms a copy itself.
  ///
  /// [origin] is the tapped button, which an iPad's popup points at.
  Future<bool> shareWithCopyLink(
    ShareLink link, {
    required String copyLinkLabel,
    required String copiedLabel,
    Rect? origin,
  }) async {
    try {
      final answer = await _channel.invokeMethod<String>('share', {
        'text': link.text,
        'url': link.url,
        'subject': link.subject,
        'copyLinkLabel': copyLinkLabel,
        'copiedLabel': copiedLabel,
        if (origin != null)
          'origin': [origin.left, origin.top, origin.width, origin.height],
      });
      return answer == 'copiedLink';
    } on MissingPluginException {
      // A build with no channel behind it: the popup as it was, without the row.
      await SharePlus.instance.share(ShareParams(
        text: link.text,
        subject: link.subject,
        sharePositionOrigin: origin,
      ));
      return false;
    }
  }

  /// The link alone on the clipboard.
  Future<void> copyLink(ShareLink link) =>
      Clipboard.setData(ClipboardData(text: link.url));

  /// Whether this browser has a share popup of its own (navigator.share).
  /// Always false off the web.
  bool get browserCanShare => browserHasSharePopup();

  /// The browser's own share popup — the caption and the link.
  Future<void> shareViaBrowser(ShareLink link) => SharePlus.instance
      .share(ShareParams(text: link.text, subject: link.subject));

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
