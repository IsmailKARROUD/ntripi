// features/auth/presentation/suspended_screen.dart — Terminal screen for a
// moderator-suspended account.
//
// Reached only from AuthInterceptor, which lands here the moment any request
// comes back with the `account_deactivated` code. Tokens are already cleared by
// then, so this is a public route — the router guard must not bounce it to
// /login.
//
// Appeals happen on the web, not in-app: a suspended account cannot call the
// API at all, so the form has to be authorized by an emailed signed link.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/appeal_link.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class SuspendedScreen extends StatelessWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nt = context.nt;

    return Scaffold(
      backgroundColor: nt.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: nt.dangerTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.gavel_outlined, size: 34, color: nt.danger),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.suspendedTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: nt.bark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.suspendedMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: nt.text2,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: openAppealPage,
                    child: Text(l10n.suspendedAppealButton),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(l10n.suspendedBackToLogin),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
