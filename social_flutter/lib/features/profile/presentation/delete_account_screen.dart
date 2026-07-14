// features/profile/presentation/delete_account_screen.dart
//
// Screen: /settings/delete-account
// Lets the authenticated user permanently delete their account.
// Re-authentication depends on account type (User.hasPassword):
//   • password accounts  → re-enter password
//   • passwordless (SSO) accounts → re-authenticate with the provider (Google
//     today; native picker on mobile, rendered GoogleWebButton on web)
// Both paths go through the type-to-confirm dialog first.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/auth/google_signin_service.dart';
import 'package:social_flutter/core/auth/google_web_button.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

const _kError = Color(0xFFBA1A1A);
const _kErrorContainer = Color(0xFFFFDAD6);
const _kErrorBorder = Color(0xFFFFB4AB);
const _kErrorText = Color(0xFF410002);

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  // Web-only: the Google button can't be awaited, so we gate its rendering
  // behind the type-to-confirm step by flipping this once the user confirms.
  bool _webConfirmed = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _confirmTyped() async {
    final l10n = AppLocalizations.of(context)!;
    return confirmTypedDestructiveAction(
      context: context,
      title: l10n.deleteAccountConfirmTitle,
      message: l10n.deleteAccountConfirmMessage,
      requiredText: l10n.deleteAccountRequiredText,
      confirmLabel: l10n.deleteAccountConfirmLabel,
      hintText: l10n.deleteAccountRequiredText,
    );
  }

  // ── Password account ──────────────────────────────────────────────────────

  Future<void> _confirmAndDeleteWithPassword() async {
    if (!await _confirmTyped() || !mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.deleteAccount(password: _passwordController.text);
      await _finishLoggedOut();
    } on PasswordIncorrectException {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.deleteAccountPasswordError);
    } catch (_) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.deleteAccountGenericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Passwordless (Google) account ─────────────────────────────────────────

  /// Mobile/desktop: confirm, then run the native Google picker for a fresh
  /// ID token and delete. (Web uses the rendered button + [_deleteWithGoogleToken].)
  Future<void> _confirmAndReauthGoogleMobile() async {
    if (!await _confirmTyped() || !mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    String? idToken;
    try {
      idToken = await GoogleSignInService.instance.obtainIdToken();
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.deleteAccountGenericError;
          _isLoading = false;
        });
      }
      return;
    }
    if (idToken == null) {
      if (mounted) setState(() => _isLoading = false); // user canceled the picker
      return;
    }
    await _deleteWithGoogleToken(idToken);
  }

  /// Web: reveal the rendered Google button only after the type-to-confirm step.
  Future<void> _confirmGoogleWeb() async {
    if (await _confirmTyped() && mounted) {
      setState(() => _webConfirmed = true);
    }
  }

  /// Shared final step for both Google paths: delete with the fresh ID token.
  Future<void> _deleteWithGoogleToken(String idToken) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.deleteAccount(googleIdToken: idToken);
      await _finishLoggedOut();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _errorMessage = AppLocalizations.of(context)!.deleteAccountGenericError);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishLoggedOut() async {
    await ref.read(authNotifierProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profileAsync = ref.watch(myProfileProvider);
    return SavingOverlay(
      saving: _isLoading,
      tint: kSurface,
      child: Scaffold(
        backgroundColor: kSurface,
        resizeToAvoidBottomInset: false,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity,
            ),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: EditorialTopBar(title: l10n.deleteAccountTitle),
                ),
                Container(height: 1, color: kBorder),
                Expanded(
                  child: profileAsync.when(
                    loading: () => const Center(child: NTripiRingLoader(size: 28)),
                    error: (_, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.deleteAccountGenericError,
                          style: const TextStyle(color: _kError),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    data: (user) => _buildBody(context, l10n, user),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _warningCard(l10n),
          const SizedBox(height: 32),

          // Re-auth prompt differs by account type.
          if (user.hasPassword)
            ..._passwordInputs(context, l10n)
          else
            _googleExplain(l10n),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: _kError),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 32),

          if (user.hasPassword)
            _passwordDeleteButton(l10n)
          else
            _googleActionArea(l10n),
          const SizedBox(height: 12),

          OutlinedButton(
            onPressed: _isLoading ? null : () => context.pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(l10n.cancel, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _warningCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kErrorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kErrorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _kError),
              const SizedBox(width: 8),
              Text(
                l10n.deleteAccountCannotUndo,
                style: const TextStyle(
                  color: _kError,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.deleteAccountWillRemove,
            style: const TextStyle(color: _kErrorText, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...[
            l10n.deleteAccountBullet1,
            l10n.deleteAccountBullet2,
            l10n.deleteAccountBullet3,
          ].map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: _kErrorText)),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(color: _kErrorText, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.deleteAccountNote,
            style: const TextStyle(
              color: _kError,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _passwordInputs(BuildContext context, AppLocalizations l10n) {
    return [
      Text(
        l10n.deleteAccountEnterPassword,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          label: LabelWithHelp(
            label: l10n.deleteAccountPasswordLabel,
            helpTitle: l10n.deleteAccountPasswordHelpTitle,
            helpMessage: l10n.deleteAccountPasswordHelpMessage,
          ),
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.lock_outlined),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ),
    ];
  }

  Widget _passwordDeleteButton(AppLocalizations l10n) {
    return OfflineGate(
      builder: (online) => ElevatedButton(
        onPressed: (_isLoading || !online) ? null : _confirmAndDeleteWithPassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kError,
          foregroundColor: kSurface,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isLoading
            ? const NTripiRingLoader(size: 20)
            : Text(l10n.deleteAccountButton, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _googleExplain(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: kText2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.deleteAccountGoogleExplain,
              style: const TextStyle(fontSize: 13, color: kText2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleActionArea(AppLocalizations l10n) {
    if (kIsWeb) {
      // Web: the ID token arrives via the rendered button's callback, so gate
      // the button behind the type-to-confirm step (see [_webConfirmed]).
      if (!_webConfirmed) {
        return OfflineGate(
          builder: (online) => ElevatedButton(
            onPressed: (_isLoading || !online) ? null : _confirmGoogleWeb,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kError,
              foregroundColor: kSurface,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(l10n.deleteAccountButton, style: const TextStyle(fontSize: 16)),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.deleteAccountGoogleButton,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: kText2),
          ),
          const SizedBox(height: 8),
          OfflineGate(
            builder: (_) => GoogleWebButton(
              onIdToken: _deleteWithGoogleToken,
              onError: (_) => setState(() =>
                  _errorMessage = AppLocalizations.of(context)!.deleteAccountGenericError),
            ),
          ),
        ],
      );
    }
    // Mobile/desktop: one red button drives confirm → native picker → delete.
    return OfflineGate(
      builder: (online) => ElevatedButton(
        onPressed:
            (_isLoading || !online) ? null : _confirmAndReauthGoogleMobile,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kError,
          foregroundColor: kSurface,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isLoading
            ? const NTripiRingLoader(size: 20)
            : Text(l10n.deleteAccountButton, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
