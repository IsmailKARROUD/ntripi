// features/profile/presentation/widgets/profile_unavailable_view.dart
//
// What a profile looks like when the server answers 404: deleted, banned, or
// blocked in either direction.
//
// The copy is identical for all three on purpose. The backend already returns
// one indistinguishable response (see `_require_not_blocked` in users.py) so
// that a blocked user cannot tell a block from an ordinary absence; wording
// that hinted at a block here would give away exactly what that 404 protects.
//
// Deliberately no Retry button — a 404 for a gone account will answer 404
// forever, so offering a retry only teaches people it does nothing.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class ProfileUnavailableView extends StatelessWidget {
  const ProfileUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    // The profile screen has no AppBar — its back arrow lives on the hero,
    // which is never built on the error branch. Without this the route is a
    // dead end on platforms with no system back gesture.
    final canPop = Navigator.of(context).canPop();

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
              child: Icon(Icons.person_off_outlined, size: 28, color: nt.text2),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.profileUnavailableTitle,
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
              l10n.profileUnavailableMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: nt.text2, height: 1.5),
            ),
            if (canPop) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.goBack),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
