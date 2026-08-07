// features/auth/presentation/widgets/tos_gate.dart
//
// Blocks the whole app for a signed-in user who has not accepted the ToS
// revision now in force.
//
// It is mounted in MaterialApp.router's `builder` rather than inside _AppShell
// because many routes (/itineraries/*, /profile/:userId, /notifications) are
// declared at the root level and would slip past a shell-mounted gate.
//
// Inert unless authenticated AND the profile has loaded AND tos_current is
// false, which is what keeps /splash, /login, /register and /suspended working
// with no route allowlist to fall out of date.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/features/auth/presentation/accept_terms_screen.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';

class TosGate extends ConsumerWidget {
  final Widget child;

  const TosGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked before the profile so /splash, /login and /register never fire a
    // /users/me they have no token for.
    final signedIn = ref.watch(hasSessionProvider).value ?? false;
    if (!signedIn) return child;

    // Loading and error both fall through: a profile we could not read is not
    // evidence of a stale agreement, and blocking the app on a failed request
    // would strand people offline.
    final profile = ref.watch(myProfileProvider).value;
    if (profile == null || profile.tosCurrent) return child;

    return const AcceptTermsScreen();
  }
}
