// presentation/widgets/share_link_action.dart — what every Share button does.
//
// On a phone: the phone's own share popup. Other apps get the caption and the
// link, and the popup's own Copy copies both, with one row added — Copy link —
// for the link alone (ShareService.shareWithCopyLink). On the web, whose share
// popups take no extra row: a two-item menu, Copy link and Share via…; or,
// where the browser has no share popup at all, the link copied at once.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/features/itineraries/data/share_service.dart';
import 'package:ntripi/features/itineraries/providers/itinerary_providers.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// Shares [link] from the Share button [anchor] belongs to — the button itself,
/// which an iPad's popup and the web menu point at.
Future<void> shareLink(BuildContext anchor, WidgetRef ref, ShareLink link) async {
  final service = ref.read(shareServiceProvider);
  final l10n = AppLocalizations.of(anchor)!;
  final messenger = ScaffoldMessenger.maybeOf(anchor);
  final origin = _boundsOf(anchor);

  void sayCopied() => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.shareLinkCopied)));

  if (!kIsWeb) {
    final copied = await service.shareWithCopyLink(
      link,
      copyLinkLabel: l10n.shareCopyLink,
      copiedLabel: l10n.shareLinkCopied,
      origin: origin,
    );
    if (copied) sayCopied();
    return;
  }

  if (!service.browserCanShare) {
    await service.copyLink(link);
    sayCopied();
    return;
  }

  if (origin == null || !anchor.mounted) return;
  final overlay =
      Overlay.of(anchor).context.findRenderObject()! as RenderBox;
  await showMenu<void>(
    context: anchor,
    position: RelativeRect.fromRect(origin, Offset.zero & overlay.size),
    items: [
      PopupMenuItem(
        // onTap, not the menu's result: the browser opens its share popup only
        // from inside the tap that asked for it.
        onTap: () async {
          await service.copyLink(link);
          sayCopied();
        },
        child: _MenuRow(icon: Icons.link_rounded, label: l10n.shareCopyLink),
      ),
      PopupMenuItem(
        onTap: () => service.shareViaBrowser(link),
        child: _MenuRow(icon: Icons.ios_share_rounded, label: l10n.shareVia),
      ),
    ],
  );
}

/// [context]'s box in global coordinates, or null before it is laid out.
Rect? _boundsOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      );
}
