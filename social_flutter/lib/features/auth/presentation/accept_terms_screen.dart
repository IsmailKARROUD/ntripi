// features/auth/presentation/accept_terms_screen.dart
//
// Shown to a signed-in user whose accepted ToS revision is no longer the one in
// force. Blocking by design: the agreement is what the account exists under, so
// an unaccepted revision means there is nothing to browse under.
//
// It always carries a sign-out action. A user who will not accept must be able
// to leave — a gate with no exit is a lockout, and they still need to reach
// their account to delete it.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/ntripi_logo.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/auth/presentation/widgets/tos_agreement_row.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/locale_picker_button.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';
import 'package:social_flutter/shared/widgets/theme_picker_button.dart';

class AcceptTermsScreen extends ConsumerStatefulWidget {
  const AcceptTermsScreen({super.key});

  @override
  ConsumerState<AcceptTermsScreen> createState() => _AcceptTermsScreenState();
}

class _AcceptTermsScreenState extends ConsumerState<AcceptTermsScreen> {
  bool _accepted = false;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _accept(AppLocalizations l10n) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).acceptTos();
      // Refreshing the profile is what lowers the gate: TosGate watches
      // myProfileProvider, so the new tos_current releases the whole app.
      ref.invalidate(myProfileProvider);
    } on DioException catch (e) {
      setState(() => _errorMessage = extractErrorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return SavingOverlay(
      saving: _isLoading,
      tint: nt.surface,
      child: Scaffold(
        backgroundColor: nt.surface,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          NtripiLogo(size: 28, showWordmark: true),
                          Spacer(),
                          ThemePickerButton(),
                          SizedBox(width: 8),
                          LocalePickerButton(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.acceptTermsTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: nt.bark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.acceptTermsBody,
                      style: TextStyle(fontSize: 14, color: nt.text2, height: 1.6),
                    ),
                    const SizedBox(height: 28),
                    TosAgreementRow(
                      accepted: _accepted,
                      onChanged: (v) => setState(() => _accepted = v),
                      showHelp: false,
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: nt.dangerTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(fontSize: 13, color: nt.danger),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ElevatedButton(
                      onPressed:
                          (_accepted && !_isLoading) ? () => _accept(l10n) : null,
                      child: Text(l10n.acceptTermsButton),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => ref.read(authNotifierProvider.notifier).logout(),
                      child: Text(l10n.logoutConfirmButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
