import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool showPassword = false;
  bool rememberMe = false;
  bool isLoading = false;
  String? errorMessage;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  Future<void> handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithEmail(
        emailController.text.trim(),
        passwordController.text,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, "/dashboard");
      }
    } on Exception catch (e) {
      setState(() {
        errorMessage = _parseAuthError(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _parseAuthError(String error) {
    if (error.contains('user-not-found')) return 'No account found with this email.';
    if (error.contains('wrong-password')) return 'Incorrect password.';
    if (error.contains('invalid-email')) return 'Invalid email address.';
    if (error.contains('user-disabled')) return 'This account has been disabled.';
    if (error.contains('too-many-requests')) return 'Too many attempts. Try again later.';
    if (error.contains('invalid-credential')) return 'Invalid email or password.';
    return 'Sign in failed. Please try again.';
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Logo
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.scale,
                      size: 32,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 18),

                  Text(
                    "Weighbridge Manager",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Tabs (Login / Sign Up)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              "Login",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(height: 2, color: colorScheme.primary),
                          ],
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.pushNamed(context, "/signup");
                          },
                          child: Column(
                            children: [
                              Text(
                                "Sign Up",
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              Container(height: 2, color: Colors.transparent),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Error message
                  if (errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 18, color: colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Email Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Email",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      hintText: "Enter your email",
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Password Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Password",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: passwordController,
                    obscureText: !showPassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: "Enter your password",
                      suffixIcon: IconButton(
                        icon: Icon(
                          showPassword ? Icons.visibility_off : Icons.visibility,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() => showPassword = !showPassword);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Remember + Forgot
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: rememberMe,
                            onChanged: (val) {
                              setState(() => rememberMe = val ?? false);
                            },
                          ),
                          const Text("Remember me"),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, "/reset");
                        },
                        child: const Text("Forgot Password?"),
                      )
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLoading ? null : handleSignIn,
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Log in",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
