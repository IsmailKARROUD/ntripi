import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/ntripi_logo.dart';
import 'package:social_flutter/features/auth/domain/username_validator.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';

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

  void _showTosSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                color: const Color(0xFFE4EDE6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Terms of Service',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kBark,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text(
                  _tosSummary ?? 'Loading…',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF5A7562), height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_tosAccepted) {
      setState(() => _errorMessage = 'You must accept the Terms of Service.');
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
      if (mounted) context.go('/profile/me');
    } on DioException catch (e) {
      setState(() => _errorMessage = extractErrorMessage(e));
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
    return Scaffold(
      backgroundColor: kSand,
      body: SafeArea(
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
                    ],
                  ),
                ),

                // Heading
                const Text(
                  'Create account',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: kBark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Join thousands of explorers sharing routes',
                  style: TextStyle(fontSize: 14, color: Color(0xFF5A7562)),
                ),
                const SizedBox(height: 24),

                // Display name
                _FieldLabel('Display Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Your name (optional)'),
                  validator: DisplayNameValidator.validate,
                ),
                const SizedBox(height: 12),

                // Username
                _FieldLabel('Username'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    hintText: 'yourhandle',
                    prefixText: '@',
                    prefixStyle: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF93A898),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  validator: UsernameValidator.validate,
                ),
                const SizedBox(height: 12),

                // Email
                _FieldLabel('Email'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'you@example.com'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required.';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                      return 'Please enter a valid email.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Password
                _FieldLabel('Password'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Min. 8 characters',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF93A898),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required.';
                    if (v.length < 8) return 'Must be at least 8 characters.';
                    if (!v.contains(RegExp(r'[0-9]'))) {
                      return 'Must contain at least one digit.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Confirm password
                _FieldLabel('Confirm Password'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF93A898),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please confirm your password.';
                    if (v != _passwordController.text) return 'Passwords do not match.';
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
                            const Text(
                              'I agree to the ',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5A7562),
                              ),
                            ),
                            GestureDetector(
                              onTap: _showTosSheet,
                              child: const Text(
                                'Terms of Service',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kForest,
                                ),
                              ),
                            ),
                            const Text(
                              ' and ',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5A7562),
                              ),
                            ),
                            const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kForest,
                              ),
                            ),
                          ],
                        ),
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
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_tosAccepted) ? null : _register,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Account'),
                  ),
                ),
                const SizedBox(height: 28),

                // Sign in link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A7562)),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(
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
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF5A7562),
      ),
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
        style: const TextStyle(color: Color(0xFF410002), fontSize: 13),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE4EDE6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D001408),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 14, color: kBark),
      ),
    );
  }
}
