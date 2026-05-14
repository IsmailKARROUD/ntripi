// features/profile/presentation/delete_account_screen.dart
//
// Screen: /settings/delete-account
// Lets the authenticated user permanently delete their account.
// Requires password re-entry and an explicit confirmation dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/shared/widgets/editorial_widgets.dart';
import 'package:social_flutter/shared/widgets/field_help.dart';

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

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete() async {
    final typed = await confirmTypedDestructiveAction(
      context: context,
      title: 'Delete your account?',
      message: 'Your account, itineraries, follows, and ratings will be '
          'anonymized or deleted per our privacy policy. You will be signed '
          'out immediately. This cannot be undone.',
      requiredText: 'DELETE MY ACCOUNT',
      confirmLabel: 'Delete my account',
      hintText: 'DELETE MY ACCOUNT',
    );
    if (!typed || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.deleteAccount(_passwordController.text);
      await ref.read(authNotifierProvider.notifier).logout();
      if (mounted) context.go('/login');
    } on PasswordIncorrectException {
      setState(() => _errorMessage = 'Incorrect password. Please try again.');
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const SafeArea(
                bottom: false,
                child: EditorialTopBar(title: 'Delete Account'),
              ),
              Container(height: 1, color: kBorder),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Warning card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _kErrorContainer,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _kErrorBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: _kError),
                                SizedBox(width: 8),
                                Text(
                                  'This cannot be undone',
                                  style: TextStyle(
                                    color: _kError,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Deleting your account will permanently remove:',
                              style: TextStyle(color: _kErrorText, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            ...[
                              'Your profile and all personal data',
                              'All your itineraries and stops',
                              'Your follow relationships',
                            ].map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ',
                                        style: TextStyle(color: _kErrorText)),
                                    Expanded(
                                      child: Text(
                                        item,
                                        style: const TextStyle(
                                            color: _kErrorText, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Ratings you gave to other itineraries will be '
                              'kept anonymously as community data.',
                              style: TextStyle(
                                color: _kError,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text(
                        'Enter your password to confirm',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          label: const LabelWithHelp(
                            label: 'Password',
                            helpTitle: 'Confirm password',
                            helpMessage:
                                'Re-enter your password to confirm deletion. '
                                'Account deletion is permanent and cannot be undone.',
                          ),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: _kError),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 32),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _confirmAndDelete,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kError,
                          foregroundColor: kSurface,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: kSurface),
                              )
                            : const Text('Delete My Account',
                                style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(height: 12),

                      OutlinedButton(
                        onPressed: _isLoading ? null : () => context.pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child:
                            const Text('Cancel', style: TextStyle(fontSize: 16)),
                      ),
                    ],
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
