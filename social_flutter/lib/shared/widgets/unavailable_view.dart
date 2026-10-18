// shared/widgets/unavailable_view.dart
//
// The one layout for "this can't be shown": a circled icon, a title, a line of
// explanation and a way out. Profiles and trips each say why in their own
// words (ProfileUnavailableView, ItineraryUnavailableView); this keeps them
// looking like one app.
//
// No Retry by design: everything that uses it is an answer that will not
// change by asking again — a gone account, a trip someone else keeps private.

import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';

class UnavailableView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// The screen's way out, or null where there is nowhere to go back to.
  final VoidCallback? onBack;

  const UnavailableView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: nt.mist, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: nt.text2),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: nt.bark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: nt.text2, height: 1.5),
            ),
            if (onBack != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: onBack,
                child: Text(l10n.goBack),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
