import 'package:dio/dio.dart';
import 'package:social_flutter/core/utils/apple_platform.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/auth/google_signin_service.dart';
import 'package:social_flutter/core/auth/google_web_button.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/ntripi_logo.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/auth/presentation/widgets/google_tos_consent_sheet.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/appeal_link.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/locale_picker_button.dart';
import 'package:social_flutter/shared/widgets/theme_picker_button.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  /// Backend `code` behind [_errorMessage] — drives the appeal link on a
  /// suspension (the interceptor also routes to /suspended, but the user can
  /// walk back here and retry).
  String? _errorCode;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Records the message *and* the backend code — the banner needs the code to
  /// decide whether to offer the appeal link.
  void _showDioError(DioException e) {
    setState(() {
      _errorMessage = extractErrorMessage(e, AppLocalizations.of(context)!);
      _errorCode = apiErrorCode(e);
    });
  }

  void _showGenericError() {
    setState(() {
      _errorMessage = AppLocalizations.of(context)!.errorGenericRetry;
      _errorCode = null;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final result = await repo.login(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      );
      ref.read(authNotifierProvider.notifier).setAuthenticated(result.userId);
      ref.invalidate(myProfileProvider);
      ref.invalidate(myItinerariesProvider);
      ref.invalidate(savedItinerariesProvider);
      if (mounted) context.go('/profile/me');
    } on DioException catch (e) {
      _showDioError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Mobile/desktop Google sign-in: run the native picker, then exchange the
  /// ID token with the backend. (Web uses the rendered button + [_onWebGoogleIdToken].)
  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      final idToken = await GoogleSignInService.instance.obtainIdToken();
      if (idToken == null) return; // user canceled the picker
      await _completeGoogleSignIn(idToken);
    } on DioException catch (e) {
      if (mounted) {
        _showDioError(e);
      }
    } catch (_) {
      if (mounted) {
        _showGenericError();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Called by the web rendered Google button once it yields an ID token.
  Future<void> _onWebGoogleIdToken(String idToken) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      await _completeGoogleSignIn(idToken);
    } on DioException catch (e) {
      if (mounted) {
        _showDioError(e);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onWebGoogleError(Object error) {
    if (mounted) _showGenericError();
  }

  /// Shared tail for both flows: persist tokens (done in the repo) then route in.
  ///
  /// A brand-new Google account 400s `tos_required` — the server will not create
  /// an account for someone who has agreed to nothing. We show the agreement and
  /// re-post the SAME ID token with the flag set: Google ID tokens live about an
  /// hour and verification is stateless, so a second post is fine. Signing in to
  /// an existing account never reaches that branch, so returning users see no
  /// sheet.
  Future<void> _completeGoogleSignIn(String idToken) async {
    final repo = ref.read(authRepositoryProvider);
    AuthResult result;
    try {
      result = await repo.loginWithGoogle(idToken: idToken);
    } on DioException catch (e) {
      if (apiErrorCode(e) != kTosRequiredCode || !mounted) rethrow;
      if (!await showGoogleTosConsentSheet(context)) return; // user declined
      result = await repo.loginWithGoogle(idToken: idToken, tosAccepted: true);
    }
    ref.read(authNotifierProvider.notifier).setAuthenticated(result.userId);
    ref.invalidate(myProfileProvider);
    ref.invalidate(myItinerariesProvider);
    ref.invalidate(savedItinerariesProvider);
    if (mounted) context.go('/profile/me');
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
          constraints: BoxConstraints(maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Theme + language pickers — top-right, before logo
                const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ThemePickerButton(),
                        Spacer(),
                        LocalePickerButton(),
                      ],
                    ),
                  ),
                ),

                // Logo
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: NtripiLogo(size: 48, showWordmark: true),
                  ),
                ),

                // Heading
                Text(
                  l10n.loginTitle,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: nt.bark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.loginSubtitle,
                  style: TextStyle(fontSize: 14, color: nt.text2),
                ),
                const SizedBox(height: 28),

                // Email or username field
                _FieldLabel(
                  l10n.loginEmailLabel,
                  helpTitle: l10n.loginEmailLabel,
                  helpMessage: l10n.loginEmailHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    hintText: l10n.loginEmailHint,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l10n.required : null,
                ),
                const SizedBox(height: 14),

                // Password field
                _FieldLabel(
                  l10n.loginPasswordLabel,
                  helpTitle: l10n.loginPasswordLabel,
                  helpMessage: l10n.loginPasswordHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: nt.text3,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? l10n.required : null,
                ),

                // Forgot password
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: Text(l10n.loginForgotPassword),
                  ),
                ),
                const SizedBox(height: 4),

                // Error banner — a suspension gets a way out, not a dead end
                if (_errorMessage != null) ...[
                  _ErrorBanner(
                    _errorMessage!,
                    onAppeal: _errorCode == kAccountDeactivatedCode
                        ? openAppealPage
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Sign In button
                SizedBox(
                  height: 54,
                  child: OfflineGate(
                    builder: (online) => ElevatedButton(
                      onPressed: (_isLoading || !online) ? null : _login,
                      child: _isLoading
                          ? const NTripiRingLoader(size: 22)
                          : Text(l10n.loginSignIn),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Divider
                _OrDivider(label: l10n.loginOrContinueWith),
                const SizedBox(height: 20),

                // Social sign-in buttons
                Row(
                  children: [
                    Expanded(
                      // Web can't use authenticate() — render Google's own button.
                      child: OfflineGate(
                        builder: (online) => kIsWeb
                            ? GoogleWebButton(
                                onIdToken: _onWebGoogleIdToken,
                                onError: _onWebGoogleError,
                              )
                            : _SocialButton(
                                label: 'Google',
                                icon: Text(
                                  'G',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: nt.bark,
                                  ),
                                ),
                                onPressed: (_isLoading || !online)
                                    ? null
                                    : _loginWithGoogle,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                   isApplePlatform() ? Expanded(
                      child: _SocialButton(
                        label: 'Apple',
                        icon: Icon(Icons.apple, size: 20, color: nt.bark),
                      ),
                    ) : const SizedBox.shrink(),
                  ],
                ),
                const SizedBox(height: 32),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.loginNoAccount,
                      style: TextStyle(
                        fontSize: 14,
                        color: nt.text2,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/register'),
                      child: Text(
                        l10n.loginSignUp,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: nt.forest,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),),),);
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  final String? helpTitle;
  final String? helpMessage;
  const _FieldLabel(this.text, {this.helpTitle, this.helpMessage});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: nt.text2,
    );
    if (helpTitle == null || helpMessage == null) {
      return Text(text, style: labelStyle);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(text, style: labelStyle),
        const SizedBox(width: 2),
        FieldHelpIcon(
          helpTitle: helpTitle!,
          helpMessage: helpMessage!,
          size: 16,
          color: nt.text2,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  /// When set, the banner grows an appeal link under the message. Only a
  /// moderator suspension passes one — every other error is not appealable.
  final VoidCallback? onAppeal;

  const _ErrorBanner(this.message, {this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(
              color: cs.onErrorContainer,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          if (onAppeal != null)
            TextButton(
              onPressed: onAppeal,
              style: TextButton.styleFrom(
                foregroundColor: cs.onErrorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppLocalizations.of(context)!.suspendedAppealButton,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  final String label;
  const _OrDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: nt.text3),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  const _SocialButton({required this.label, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return OutlinedButton(
      // Default (no onPressed, e.g. the Apple placeholder): "coming soon".
      onPressed: onPressed ??
          () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.comingSoon)),
              ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        backgroundColor: nt.surface,
        side: BorderSide(color: nt.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: nt.bark,
            ),
          ),
        ],
      ),
    );
  }
}
