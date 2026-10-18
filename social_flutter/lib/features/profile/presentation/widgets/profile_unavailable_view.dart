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
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';

class ProfileUnavailableView extends StatelessWidget {
  /// The profile screen's way out, or null on your own profile, which is home
  /// and has nowhere to go back to.
  ///
  /// The profile screen has no AppBar — its back arrow lives on the hero, which
  /// is never built on the error branch, so without this the route is a dead
  /// end. It is not gated on `canPop`: a notification about an account that
  /// has since gone can open this page as the only route, which is exactly
  /// when it needs a way out most.
  final VoidCallback? onBack;

  const ProfileUnavailableView({super.key, this.onBack});

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
