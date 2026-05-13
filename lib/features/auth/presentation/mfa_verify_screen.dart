import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/auth/presentation/animated_background.dart';
import 'package:weighbridgemanagement/shared/providers/mfa_provider.dart';

class MfaVerifyScreen extends ConsumerStatefulWidget {
  final MultiFactorResolver resolver;
  const MfaVerifyScreen({super.key, required this.resolver});

  @override
  ConsumerState<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends ConsumerState<MfaVerifyScreen> with SingleTickerProviderStateMixin {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
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
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _otpControllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length != 6) {
      setState(() => _error = 'Enter all 6 digits');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final mfa = ref.read(mfaServiceProvider);
      final hint = widget.resolver.hints.first;
      await mfa.resolveSignIn(widget.resolver, _otp, hint);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'invalid-verification-code'
            ? 'Invalid code. Please try again.'
            : 'Verification failed: ${e.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Verification failed. Try again.');
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]),
                  border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.3)),
                  boxShadow: [BoxShadow(color: const Color(0xFF43A047).withValues(alpha: 0.15), blurRadius: 16)],
                ),
                child: const Icon(Icons.security_rounded, color: Color(0xFF2E7D32), size: 28),
              ),
              const SizedBox(height: 20),
              const Text('Two-Factor Authentication',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text('Enter the 6-digit code from your authenticator app',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 32),

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
                const SizedBox(height: 20),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) => Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 8, right: i == 2 ? 12 : 0),
                  child: SizedBox(
                    width: 48, height: 56,
                    child: TextField(
                      controller: _otpControllers[i],
                      focusNode: _focusNodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                      decoration: InputDecoration(
                        filled: true, fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43A047), width: 2)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 5) {
                          _focusNodes[i + 1].requestFocus();
                        }
                        if (v.isEmpty && i > 0) {
                          _focusNodes[i - 1].requestFocus();
                        }
                        if (_otp.length == 6) {
                          _verify();
                        }
                      },
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 28),

              GestureDetector(
                onTap: _loading ? null : _verify,
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
                        : const Text('Verify', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
