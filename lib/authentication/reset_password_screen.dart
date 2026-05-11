import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool emailSent = false;
  String? errorMessage;

  Future<void> handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.sendPasswordResetEmail(emailController.text.trim());
      setState(() => emailSent = true);
    } on Exception catch (e) {
      final err = e.toString();
      if (err.contains('user-not-found')) {
        setState(() => errorMessage = 'No account found with this email.');
      } else {
        setState(() => errorMessage = 'Failed to send reset email. Try again.');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            margin: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 18,
                      )
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primaryContainer,
                          ),
                          child: Icon(
                            emailSent ? Icons.check : Icons.lock_reset,
                            size: 32,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 18),

                        Text(
                          emailSent ? "Email Sent!" : "Reset Password",
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),

                        Text(
                          emailSent
                              ? "Check your inbox for a password reset link."
                              : "Enter your email address and we'll send you a reset link.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),

                        if (!emailSent) ...[
                          // Error
                          if (errorMessage != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                errorMessage!,
                                style: TextStyle(fontSize: 13, color: colorScheme.onErrorContainer),
                              ),
                            ),

                          // Email
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Email Address",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return 'Email is required';
                              if (!value.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                            decoration: const InputDecoration(
                              hintText: "user@company.com",
                              suffixIcon: Icon(Icons.mail_outline),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Send button
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: isLoading ? null : handleSendResetLink,
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text("Send Reset Link",
                                      style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 14),

                          Text(
                            "Check your spam folder if you don't see the email.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Back to Login
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_back, size: 18, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                "Back to Login",
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
