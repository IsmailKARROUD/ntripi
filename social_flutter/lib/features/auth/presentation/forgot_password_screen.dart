import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        foregroundColor: kBark,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: _sent ? _buildSent(l10n) : _buildForm(l10n),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.forgotPasswordTitle,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kBark),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.forgotPasswordSubtitle,
            style: const TextStyle(fontSize: 14, color: kText2),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.forgotPasswordEmailLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kText2),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.required : null,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(_errorMessage!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const NTripiRingLoader(size: 22)
                  : Text(l10n.forgotPasswordSubmit),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.mark_email_read_outlined, size: 56, color: kForest),
        const SizedBox(height: 16),
        Text(
          l10n.forgotPasswordSentTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBark),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.forgotPasswordSentBody,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: kText2),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDAD),
        border: Border.all(color: const Color(0xFFFFB4AB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: Color(0xFF410002)),
      ),
    );
  }
}
