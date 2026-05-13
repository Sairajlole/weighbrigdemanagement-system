import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/auth/presentation/animated_background.dart';
import 'package:weighbridgemanagement/features/auth/presentation/mfa_verify_screen.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/google_auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = false;
  bool _loading = false;
  String? _error;

  late AnimationController _cardController;
  late Animation<double> _cardScale;
  late Animation<double> _cardOpacity;

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _cardScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutBack),
    );
    _cardOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardController, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _cardController.forward();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthMultiFactorException catch (e) {
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MfaVerifyScreen(resolver: e.resolver)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(googleSignInServiceProvider).signIn();
    } on FirebaseAuthMultiFactorException catch (e) {
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MfaVerifyScreen(resolver: e.resolver)),
        );
      }
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String error) {
    if (error.contains('user-not-found')) return 'No account found with this email.';
    if (error.contains('wrong-password') || error.contains('invalid-credential')) return 'Invalid email or password.';
    if (error.contains('too-many-requests')) return 'Too many attempts. Try again later.';
    if (error.contains('popup-closed-by-user')) return 'Sign-in cancelled.';
    if (error.contains('network-request-failed')) return 'Network error. Check your connection.';
    if (error.contains('google-sign-in-not-configured') || error.contains('PlatformException') || error.contains('missing support')) {
      return 'Google Sign-In not configured. Run "flutterfire configure" to set up OAuth credentials.';
    }
    return 'Sign in failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedAuthBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: _cardController,
              builder: (context, child) => Opacity(
                opacity: _cardOpacity.value,
                child: Transform.scale(
                  scale: _cardScale.value,
                  child: child,
                ),
              ),
              child: _buildCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: 420,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.85),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B5E20).withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 16)),
          BoxShadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 1, spreadRadius: 1),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Logo
                Center(child: _AnimatedLogo()),
                const SizedBox(height: 16),
                const Center(
                  child: Text('Weighbridge Manager',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: -0.5)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text('Intelligent weighing operations',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500, letterSpacing: 0.2)),
                ),
                const SizedBox(height: 30),

                // Tabs
                _GlassyTabs(activeIndex: 0, onChanged: (i) { if (i == 1) context.go('/signup'); }),
                const SizedBox(height: 28),

                // Google
                _GoogleButton(onTap: _googleSignIn),
                const SizedBox(height: 20),

                // Divider
                Row(
                  children: [
                    Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('or', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
                  ],
                ),
                const SizedBox(height: 20),

                // Error
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],

                // Email
                _ModernField(
                  controller: _email,
                  label: 'Email',
                  hint: 'you@company.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password
                _ModernField(
                  controller: _password,
                  label: 'Password',
                  hint: 'Enter your password',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: Colors.grey.shade500),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 14),

                // Remember + Forgot
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              color: _rememberMe ? const Color(0xFF2E7D32) : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: _rememberMe ? const Color(0xFF2E7D32) : Colors.grey.shade400, width: 1.5),
                            ),
                            child: _rememberMe ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                          ),
                          const SizedBox(width: 8),
                          Text('Remember me', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go('/forgot-password'),
                      child: const Text('Forgot Password?',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Sign In Button
                _GradientButton(
                  label: 'Sign In',
                  loading: _loading,
                  onTap: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// === Animated Logo ===
class _AnimatedLogo extends StatefulWidget {
  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final bounce = sin(_controller.value * pi) * 3;
        return Transform.translate(
          offset: Offset(0, -bounce),
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 26),
          ),
        );
      },
    );
  }
}

// === Glassy Tabs ===
class _GlassyTabs extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const _GlassyTabs({required this.activeIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tab('Login', 0),
          _tab('Sign Up', 1),
        ],
      ),
    );
  }

  Widget _tab(String label, int index) {
    final isActive = activeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive ? [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
            ] : null,
          ),
          child: Center(
            child: Text(label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? const Color(0xFF1A1A1A) : Colors.grey.shade500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// === Google Button ===
class _GoogleButton extends StatefulWidget {
  final VoidCallback onTap;
  const _GoogleButton({required this.onTap});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          decoration: BoxDecoration(
            color: _hovered ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hovered ? Colors.grey.shade400 : Colors.grey.shade300),
            boxShadow: _hovered ? [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.g_mobiledata_rounded, size: 24, color: Colors.black87),
              ),
              const SizedBox(width: 10),
              const Text('Continue with Google',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333))),
            ],
          ),
        ),
      ),
    );
  }
}

// === Modern Input Field ===
class _ModernField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _ModernField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  State<_ModernField> createState() => _ModernFieldState();
}

class _ModernFieldState extends State<_ModernField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: _focused ? [
                BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
              ] : null,
            ),
            child: TextFormField(
              controller: widget.controller,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscure,
              validator: widget.validator,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w400),
                prefixIcon: Icon(widget.icon, size: 20,
                  color: _focused ? const Color(0xFF2E7D32) : Colors.grey.shade400),
                suffixIcon: widget.suffixIcon,
                filled: true,
                fillColor: _focused ? Colors.white : Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43A047), width: 2)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE53935))),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE53935), width: 2)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// === Gradient Button ===
class _GradientButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _GradientButton({required this.label, required this.loading, required this.onTap});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); if (!widget.loading) widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 50,
        transform: Matrix4.diagonal3Values(_pressed ? 0.97 : 1.0, _pressed ? 0.97 : 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.loading
                ? [const Color(0xFF66BB6A), const Color(0xFF43A047)]
                : [const Color(0xFF43A047), const Color(0xFF2E7D32)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E7D32).withValues(alpha: _pressed ? 0.2 : 0.35),
              blurRadius: _pressed ? 8 : 16,
              offset: Offset(0, _pressed ? 2 : 6),
            ),
          ],
        ),
        child: Center(
          child: widget.loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(widget.label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
        ),
      ),
    );
  }
}

// === Error Banner ===
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF9A9A).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE53935)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFFC62828), fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

