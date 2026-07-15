import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/ntripi_logo.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:social_flutter/features/auth/domain/username_validator.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/itineraries/providers/saved_itineraries_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/locale_picker_button.dart';
import 'package:social_flutter/shared/widgets/theme_picker_button.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _tosAccepted = false;
  String? _tosSummary;

  @override
  void initState() {
    super.initState();
    _loadTos();
  }

  Future<void> _loadTos() async {
    try {
      final data = await ref.read(authRepositoryProvider).fetchTos();
      if (mounted) setState(() => _tosSummary = data['summary'] as String?);
    } catch (_) {}
  }

  void _showTosSheet(AppLocalizations l10n) {
    final nt = context.nt;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: nt.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: nt.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.registerTosTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: nt.bark,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text(
                  _tosSummary ?? l10n.registerTosLoading,
                  style: TextStyle(fontSize: 14, color: nt.text2, height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register(AppLocalizations l10n) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_tosAccepted) {
      setState(() => _errorMessage = l10n.registerTosRequired);
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final result = await repo.register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        tosAccepted: true,
      );
      ref.read(authNotifierProvider.notifier).setAuthenticated(result.userId);
      ref.invalidate(myProfileProvider);
      ref.invalidate(myItinerariesProvider);
      ref.invalidate(savedItinerariesProvider);
      if (mounted) context.go('/profile/me');
    } on DioException catch (e) {
      setState(() => _errorMessage = extractErrorMessage(e, AppLocalizations.of(context)!));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
                // Back + logo row
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      _CircleIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => context.go('/login'),
                      ),
                      const SizedBox(width: 12),
                      const NtripiLogo(size: 28, showWordmark: true),
                      const Spacer(),
                      const ThemePickerButton(),
                      const SizedBox(width: 8),
                      const LocalePickerButton(),
                    ],
                  ),
                ),

                // Heading
                Text(
                  l10n.registerTitle,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: nt.bark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.registerSubtitle,
                  style: TextStyle(fontSize: 14, color: nt.text2),
                ),
                const SizedBox(height: 24),

                // Display name
                _FieldLabel(
                  l10n.registerDisplayName,
                  helpTitle: l10n.registerDisplayName,
                  helpMessage: l10n.registerDisplayNameHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(hintText: l10n.registerDisplayNameHint),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (v.trim().length > 50) return l10n.displayNameTooLong;
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Username
                _FieldLabel(
                  l10n.registerUsername,
                  helpTitle: l10n.registerUsername,
                  helpMessage: l10n.registerUsernameHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // keyboards can't be forced to Latin — drop disallowed chars as typed
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                  ],
                  decoration: InputDecoration(
                    hintText: l10n.registerUsernameHint,
                    prefixText: '@',
                    prefixStyle: TextStyle(
                      fontSize: 15,
                      color: nt.text3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.usernameRequired;
                    final trimmed = v.trim();
                    if (trimmed.length < 4) return l10n.usernameTooShort;
                    if (trimmed.length > 30) return l10n.usernameTooLong;
                    if (!UsernameValidator.isValidFormat(trimmed)) return l10n.usernameInvalidFormat;
                    if (UsernameValidator.hasConsecutiveSpecial(trimmed)) return l10n.usernameConsecutiveSpecial;
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Email
                _FieldLabel(
                  l10n.registerEmail,
                  helpTitle: l10n.registerEmail,
                  helpMessage: l10n.registerEmailHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // server rejects internationalized emails (SMTPUTF8 delivery unreliable)
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[^\x00-\x7F]')),
                  ],
                  decoration: InputDecoration(hintText: l10n.registerEmailHint),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l10n.registerEmailRequired;
                    // allowTopLevelDomains=false rejects single-label hosts (user@localhost);
                    // allowInternational=false matches the server's ASCII-only email policy.
                    if (!EmailValidator.validate(v.trim(), false, false)) {
                      return l10n.registerEmailInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Password
                _FieldLabel(
                  l10n.registerPassword,
                  helpTitle: l10n.registerPassword,
                  helpMessage: l10n.registerPasswordHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // re-validate confirm field so its mismatch error tracks edits to password
                  onChanged: (_) {
                    if (_confirmPasswordController.text.isNotEmpty) {
                      _formKey.currentState?.validate();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: l10n.registerPasswordHint,
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
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.registerPasswordRequired;
                    if (v.length < 8) return l10n.registerPasswordTooShort;
                    // bcrypt caps input at 72 bytes — non-Latin chars use 2+ bytes each
                    if (utf8.encode(v).length > 72) return l10n.passwordTooLong;
                    if (!v.contains(RegExp(r'[0-9]'))) {
                      return l10n.registerPasswordNoDigit;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Confirm password
                _FieldLabel(
                  l10n.registerConfirmPassword,
                  helpTitle: l10n.registerConfirmPassword,
                  helpMessage: l10n.registerConfirmPasswordHelp,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onFieldSubmitted: (_) => _register(l10n),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: nt.text3,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.registerConfirmRequired;
                    if (v != _passwordController.text) return l10n.registerConfirmMismatch;
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ToS row
                GestureDetector(
                  onTap: () => setState(() => _tosAccepted = !_tosAccepted),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _tosAccepted,
                        onChanged: (v) =>
                            setState(() => _tosAccepted = v ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          children: [
                            Text(
                              l10n.registerTosAgree,
                              style: TextStyle(
                                fontSize: 13,
                                color: nt.text2,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showTosSheet(l10n),
                              child: Text(
                                l10n.registerTos,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: nt.forest,
                                ),
                              ),
                            ),
                            Text(
                              l10n.registerTosAnd,
                              style: TextStyle(
                                fontSize: 13,
                                color: nt.text2,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => launchUrl(
                                Uri.parse(kPrivacyPolicyUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: Text(
                                l10n.registerPrivacyPolicy,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: nt.forest,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FieldHelpIcon(
                        helpTitle: l10n.registerTos,
                        helpMessage: l10n.registerTosHelp,
                        color: nt.text2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Error banner
                if (_errorMessage != null) ...[
                  _ErrorBanner(_errorMessage!),
                  const SizedBox(height: 16),
                ],

                // Create Account button
                SizedBox(
                  height: 54,
                  child: OfflineGate(
                    builder: (online) => ElevatedButton(
                      onPressed: (_isLoading || !_tosAccepted || !online)
                          ? null
                          : () => _register(l10n),
                      child: _isLoading
                          ? const NTripiRingLoader(size: 22)
                          : Text(l10n.registerCreateAccount),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Sign in link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.registerAlreadyHaveAccount,
                      style: TextStyle(fontSize: 14, color: nt.text2),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        l10n.registerSignIn,
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
  const _ErrorBanner(this.message);

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
      child: Text(
        message,
        style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: nt.surface,
          shape: BoxShape.circle,
          border: Border.all(color: nt.border),
          boxShadow: [
            BoxShadow(
              color: nt.shadow.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 14, color: nt.bark),
      ),
    );
  }
}
