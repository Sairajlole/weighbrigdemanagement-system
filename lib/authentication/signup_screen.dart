import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/core/models/operator_model.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  String accountType = "operator";
  bool agreedToTerms = false;
  bool isLoading = false;
  String? errorMessage;

  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController companyCodeController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  Future<void> handleCreateAccount() async {
    if (!_formKey.currentState!.validate()) return;

    if (!agreedToTerms) {
      setState(() => errorMessage = 'You must agree to the Terms of Service.');
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      setState(() => errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final firestoreService = ref.read(firestoreServiceProvider);

      // Validate company code
      final company = await firestoreService.getCompanyByLinkageCode(
        companyCodeController.text.trim(),
      );
      if (company == null) {
        setState(() => errorMessage = 'Invalid company code. Contact your admin.');
        return;
      }

      // Create Firebase Auth account
      final credential = await authService.signUpWithEmail(
        emailController.text.trim(),
        passwordController.text,
      );

      // Create operator profile in Firestore
      await firestoreService.createOperator(Operator(
        id: '',
        uid: credential.user!.uid,
        name: fullNameController.text.trim(),
        email: emailController.text.trim(),
        phone: phoneController.text.trim(),
        role: UserRole.operator,
        companyId: company.id,
        createdAt: DateTime.now(),
      ));

      if (mounted) {
        Navigator.pushReplacementNamed(context, "/linkageSubmitted");
      }
    } on Exception catch (e) {
      debugPrint('Operator signup error: $e');
      setState(() => errorMessage = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _parseError(String error) {
    if (error.contains('email-already-in-use')) return 'This email is already registered.';
    if (error.contains('weak-password')) return 'Password is too weak (min 6 characters).';
    if (error.contains('invalid-email')) return 'Invalid email address.';
    if (error.contains('permission-denied') || error.contains('PERMISSION_DENIED')) {
      return 'Firestore permission denied. Update your Firestore security rules to allow authenticated writes.';
    }
    if (error.contains('unavailable') || error.contains('UNAVAILABLE')) {
      return 'Could not connect to server. Check your internet connection.';
    }
    return 'Registration failed: ${error.length > 120 ? error.substring(0, 120) : error}';
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    companyCodeController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
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
            width: 720,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo + Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.scale, size: 30, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        "Weighbridge Manager",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tabs
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Column(
                            children: [
                              Text("Log In", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 8),
                              Container(height: 2, color: Colors.transparent),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              "Sign Up",
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
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    "Create Operator Account",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Enter your details to register as a weighbridge operator.",
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),

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
                              style: TextStyle(fontSize: 13, color: colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Account Type
                  Text(
                    "ACCOUNT TYPE",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _accountCard(
                          title: "Operator Account",
                          subtitle: "Standard access",
                          icon: Icons.local_shipping,
                          selected: accountType == "operator",
                          onTap: () => setState(() => accountType = "operator"),
                          colorScheme: colorScheme,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _accountCard(
                          title: "Admin Account",
                          subtitle: "Full access",
                          icon: Icons.scale,
                          selected: accountType == "admin",
                          onTap: () => Navigator.pushReplacementNamed(context, "/adminSignup"),
                          colorScheme: colorScheme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Row 1: Name + Email
                  Row(
                    children: [
                      Expanded(
                        child: _inputField("Full Name", fullNameController,
                            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _inputField("Email Address", emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Row 2: Phone + Company Code
                  Row(
                    children: [
                      Expanded(
                        child: _inputField("Phone Number", phoneController,
                            keyboardType: TextInputType.phone,
                            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _inputField("Company Code", companyCodeController,
                                validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                            const SizedBox(height: 4),
                            Text(
                              "Enter the code provided by your company administrator.",
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Row 3: Passwords
                  Row(
                    children: [
                      Expanded(
                        child: _inputField("Password", passwordController,
                            obscure: true, validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v.length < 6) return 'Min 6 characters';
                          return null;
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _inputField("Confirm Password", confirmPasswordController,
                            obscure: true, validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v != passwordController.text) return 'Passwords don\'t match';
                          return null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Terms
                  Row(
                    children: [
                      Checkbox(
                        value: agreedToTerms,
                        onChanged: (val) => setState(() => agreedToTerms = val ?? false),
                      ),
                      Expanded(
                        child: Wrap(
                          children: [
                            const Text("I agree to the "),
                            Text(
                              "Terms of Service",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                            const Text(" and "),
                            Text(
                              "Privacy Policy",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                            const Text("."),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Create Account Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLoading ? null : handleCreateAccount,
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Create Account", style: TextStyle(fontWeight: FontWeight.w600)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Already have an account? Log in"),
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

  Widget _inputField(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: label,
          ),
        ),
      ],
    );
  }

  Widget _accountCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: 2,
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
          color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? colorScheme.primary : colorScheme.outline,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(icon, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
