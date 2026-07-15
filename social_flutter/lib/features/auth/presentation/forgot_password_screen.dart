import 'package:dio/dio.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';

/// Requests a password-reset email. The actual reset happens on a web page
/// (opened from the email link) — this screen only triggers the email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .forgotPassword(email: _emailController.text.trim());
      // Enumeration-safe: success regardless of whether the email exists.
      if (mounted) setState(() => _sent = true);
    } on DioException catch (e) {
      setState(() =>
          _errorMessage = extractErrorMessage(e, AppLocalizations.of(context)!));
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
        appBar: AppBar(
          backgroundColor: nt.surface,
          elevation: 0,
          foregroundColor: nt.bark,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: _sent ? _buildSent(l10n) : _buildForm(l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    final nt = context.nt;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.forgotPasswordTitle,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: nt.bark),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.forgotPasswordSubtitle,
            style: TextStyle(fontSize: 14, color: nt.text2),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.forgotPasswordEmailLabel,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: nt.text2),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            // server rejects internationalized emails (SMTPUTF8 delivery unreliable)
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[^\x00-\x7F]')),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return l10n.required;
              // same ASCII-only email rule as the register screen
              if (!EmailValidator.validate(v.trim(), false, false)) {
                return l10n.registerEmailInvalid;
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(_errorMessage!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: OfflineGate(
              builder: (online) => ElevatedButton(
                onPressed: (_isLoading || !online) ? null : _submit,
                child: _isLoading
                    ? const NTripiRingLoader(size: 22)
                    : Text(l10n.forgotPasswordSubmit),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(l10n.backToSignIn),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(AppLocalizations l10n) {
    final nt = context.nt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.mark_email_read_outlined, size: 56, color: nt.forest),
        const SizedBox(height: 16),
        Text(
          l10n.forgotPasswordSentTitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: nt.bark),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.forgotPasswordSentBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: nt.text2),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            child: Text(l10n.backToSignIn),
          ),
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
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
      ),
    );
  }
}
