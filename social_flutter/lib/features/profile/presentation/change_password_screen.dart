// features/profile/presentation/change_password_screen.dart
//
// Screen: /settings/change-password
// Lets an email/password account change its password. Requires the current
// password; the server revokes all other sessions and returns a fresh token
// pair for this device (saved by the repository) so we stay signed in.
// Only reachable for accounts with a password (see the Security section gate
// in profile_edit_form.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.changePasswordSuccess)),
      );
      context.pop();
    } catch (e) {
      // Server `detail` carries the precise reason (wrong current / reuse /
      // breached); extractErrorMessage surfaces it.
      setState(() => _errorMessage = extractErrorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
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
                child: EditorialTopBar(title: l10n.changePasswordTitle),
              ),
              Container(height: 1, color: kBorder),
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
                          style: const TextStyle(color: kText2, fontSize: 14),
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
                              color: kSand,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: kDanger, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                        color: kDanger, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),

                        ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kForest,
                            foregroundColor: kSurface,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const NTripiRingLoader(size: 20)
                              : Text(l10n.changePasswordSubmit,
                                  style: const TextStyle(fontSize: 16)),
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
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: kText3,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}
