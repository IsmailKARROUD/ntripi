// features/profile/presentation/widgets/verify_email_banner.dart
//
// Shown on the signed-in user's own profile when their email is unverified.
// High-value actions (create trip, rate, follow) are gated server-side until
// the account verifies — and verification happens by signing in with Google on
// the same email, which links + verifies and returns a fresh token pair for the
// SAME account (so the user stays logged in). Reuses the exact login flow.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/auth/google_signin_service.dart';
import 'package:social_flutter/core/auth/google_web_button.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

class VerifyEmailBanner extends ConsumerStatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  ConsumerState<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends ConsumerState<VerifyEmailBanner> {
  bool _busy = false;

  /// Exchange the Google ID token for a fresh token pair on the same account,
  /// then refresh the profile so the gate reflects email_verified=true.
  Future<void> _complete(String idToken) async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).loginWithGoogle(idToken: idToken);
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.emailVerifiedSuccess)),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractErrorMessage(e, AppLocalizations.of(context)!))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mobile/desktop: run the native Google picker, then complete.
  Future<void> _verifyMobile() async {
    setState(() => _busy = true);
    try {
      final idToken = await GoogleSignInService.instance.obtainIdToken();
      if (idToken == null) {
        if (mounted) setState(() => _busy = false);
        return; // canceled
      }
      await _complete(idToken);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorGenericRetry)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    } 
  }

  /// Alternative to Google: ask the backend to email a verification link.
  Future<void> _resend() async {
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(authRepositoryProvider).resendVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.verificationEmailSent)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorGenericRetry)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 20, color: kBark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.verifyEmailTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: kBark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.verifyEmailMessage,
            style: const TextStyle(fontSize: 13, color: kText2),
          ),
          const SizedBox(height: 12),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          // Web can't use authenticate() — render Google's own button.
          else if (kIsWeb)
            OfflineGate(builder: (_) => GoogleWebButton(onIdToken: _complete))
          else
            OfflineGate(
              builder: (online) => FilledButton.icon(
                onPressed: online ? _verifyMobile : null,
                icon: const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8.0),
                  child: FaIcon(FontAwesomeIcons.google, size: 23),
                ), // Google logo
                label: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8.0),
                  child: Text(l10n.verifyEmailButton),
                ),
              ),
            ),
          // Email-link alternative for users who don't want to use Google.
         if (!_busy)
            Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8.0,end: 8.0),
              child: OfflineGate(
                builder: (online) => TextButton(
                  onPressed: online ? _resend : null,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(l10n.resendVerificationButton),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
