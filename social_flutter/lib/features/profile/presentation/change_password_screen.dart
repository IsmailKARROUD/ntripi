// features/profile/presentation/change_password_screen.dart
//
// Screen: /settings/change-password
// Lets an email/password account change its password. Requires the current
// password; the server revokes all other sessions and returns a fresh token
// pair for this device (saved by the repository) so we stay signed in.
// Only reachable for accounts with a password (see the Security section gate
// in profile_edit_form.dart).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Consequential action — it signs out every other device — so confirm
    // first via the shared Tier 2 helper (CLAUDE.md: never inline showDialog).
    final confirmed = await confirmDestructiveAction(
      context: context,
      title: l10n.changePasswordTitle,
      message: l10n.changePasswordConfirmMessage,
      confirmLabel: l10n.changePasswordSubmit,
      cancelLabel: l10n.cancel,
      icon: Icons.lock_reset_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
    } catch (e) {
      // Server `detail` carries the precise reason (wrong current / reuse /
      // breached); extractErrorMessage surfaces it. Stay on the screen so the
      // user can correct the input.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = extractErrorMessage(e, l10n);
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.changePasswordSuccess)),
    );
    context.pop();
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
                child: EditorialTopBar(title: l10n.changePasswordTitle),
              ),
              Container(height: 1, color: nt.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.changePasswordSubtitle,
                          style: TextStyle(color: nt.text2, fontSize: 14),
                        ),
                        const SizedBox(height: 24),

                        _PasswordField(
                          controller: _currentController,
                          label: l10n.changePasswordCurrentLabel,
                          obscure: _obscureCurrent,
                          onToggle: () => setState(
                              () => _obscureCurrent = !_obscureCurrent),
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.isEmpty)
                              ? l10n.registerPasswordRequired
                              : null,
                        ),
                        const SizedBox(height: 16),

                        _PasswordField(
                          controller: _newController,
                          label: l10n.changePasswordNewLabel,
                          obscure: _obscureNew,
                          onToggle: () =>
                              setState(() => _obscureNew = !_obscureNew),
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.registerPasswordRequired;
                            }
                            if (v.length < 8) {
                              return l10n.registerPasswordTooShort;
                            }
                            // bcrypt caps input at 72 bytes — non-Latin chars use 2+ bytes each
                            if (utf8.encode(v).length > 72) {
                              return l10n.passwordTooLong;
                            }
                            if (!v.contains(RegExp(r'[0-9]'))) {
                              return l10n.registerPasswordNoDigit;
                            }
                            if (v == _currentController.text) {
                              return l10n.changePasswordSameAsOld;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        _PasswordField(
                          controller: _confirmController,
                          label: l10n.changePasswordConfirmLabel,
                          obscure: _obscureConfirm,
                          onToggle: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          validator: (v) => (v != _newController.text)
                              ? l10n.changePasswordMismatch
                              : null,
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: nt.sand,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: nt.border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: nt.danger, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                        color: nt.danger, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),

                        OfflineGate(
                          builder: (online) => ElevatedButton(
                          onPressed: (_isLoading || !online) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: nt.forest,
                            foregroundColor: nt.surface,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const NTripiRingLoader(size: 20)
                              : Text(l10n.changePasswordSubmit,
                                  style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 12),

                        OutlinedButton(
                          onPressed: _isLoading ? null : () => context.pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(l10n.cancel,
                              style: const TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// A password TextFormField with the shared mask/unmask eye toggle.
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;
  final TextInputAction textInputAction;
  final void Function(String)? onSubmitted;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.validator,
    required this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: nt.text3,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}
