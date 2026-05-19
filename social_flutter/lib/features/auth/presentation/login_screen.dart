import 'package:dio/dio.dart';
import 'package:social_flutter/core/utils/apple_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/ntripi_logo.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/locale_picker_button.dart';

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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
      if (mounted) context.go('/profile/me');
    } on DioException catch (e) {
      setState(() => _errorMessage = extractErrorMessage(e, AppLocalizations.of(context)!));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kSurface,
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
                // Language picker — top-right, before logo
                const Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LocalePickerButton(),
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
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: kBark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.loginSubtitle,
                  style: const TextStyle(fontSize: 14, color: kText2),
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
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: kText3,
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
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: Text(l10n.loginForgotPassword),
                  ),
                ),
                const SizedBox(height: 4),

                // Error banner
                if (_errorMessage != null) ...[
                  _ErrorBanner(_errorMessage!),
                  const SizedBox(height: 16),
                ],

                // Sign In button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? const NTripiRingLoader(size: 22)
                        : Text(l10n.loginSignIn),
                  ),
                ),
                const SizedBox(height: 20),

                // Divider
                _OrDivider(label: l10n.loginOrContinueWith),
                const SizedBox(height: 20),

                // Social placeholder buttons
                Row(
                  children: [
                    const Expanded(
                      child: _SocialButton(
                        label: 'Google',
                        icon: Text(
                          'G',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kBark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                   isApplePlatform() ? const Expanded(
                      child: _SocialButton(
                        label: 'Apple',
                        icon: Icon(Icons.apple, size: 20, color: kBark),
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
                      style: const TextStyle(
                        fontSize: 14,
                        color: kText2,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/register'),
                      child: Text(
                        l10n.loginSignUp,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kForest,
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
    ),),);
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
    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: kText2,
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
          color: kText2,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFDAD6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB4AB)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF410002),
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  final String label;
  const _OrDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: kText3),
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
  const _SocialButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.comingSoon)),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        backgroundColor: kSurface,
        side: const BorderSide(color: kBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kBark,
            ),
          ),
        ],
      ),
    );
  }
}
