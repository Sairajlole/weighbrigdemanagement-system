import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/auth/presentation/animated_background.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  late AnimationController _cardController;

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || !_email.text.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await ref.read(firebaseAuthProvider).sendPasswordResetEmail(email: _email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send reset link. Check the email address.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              builder: (context, child) {
                final t = CurvedAnimation(parent: _cardController, curve: Curves.easeOutBack).value;
                return Opacity(
                  opacity: CurvedAnimation(parent: _cardController, curve: const Interval(0.0, 0.6)).value,
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                );
              },
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
        color: Colors.white.withValues(alpha: 0.88),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with pulse
              Center(
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]),
                    border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.3)),
                    boxShadow: [BoxShadow(color: const Color(0xFF43A047).withValues(alpha: 0.15), blurRadius: 16)],
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF2E7D32), size: 28),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text('Reset Password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: -0.5)),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _sent ? "Check your inbox for the reset link." : "Enter your email and we'll send you a reset link",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 28),

              if (_sent) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.mark_email_read_rounded, color: Color(0xFF2E7D32), size: 36),
                      const SizedBox(height: 10),
                      const Text('Reset link sent!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                      const SizedBox(height: 4),
                      Text("Check your spam folder if you don't see it.", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ] else ...[
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEF9A9A).withValues(alpha: 0.5)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE53935)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFC62828), fontWeight: FontWeight.w500))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Email Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'user@company.com',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: Icon(Icons.email_outlined, size: 20, color: Colors.grey.shade400),
                    filled: true, fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43A047), width: 2)),
                  ),
                ),
                const SizedBox(height: 22),
                _buildButton(),
              ],
              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('Back to Login', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
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

  Widget _buildButton() {
    return GestureDetector(
      onTap: _loading ? null : _submit,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF2E7D32)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Send Reset Link', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    );
  }
}

