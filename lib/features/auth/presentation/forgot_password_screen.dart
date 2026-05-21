import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _ResetStep { email, otp, newPassword, success }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  bool _loading = false;
  String? _error;
  String? _maskedPhone;
  bool _phoneSent = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String _verificationToken = '';

  @override
  void dispose() {
    _email.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _otpFocusNodes) { f.dispose(); }
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _otpValue => _otpControllers.map((c) => c.text).join();

  Future<void> _sendOTP() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendPasswordResetOTP')
          .call({'email': email});
      final data = result.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _phoneSent = data['phoneSent'] == true;
          _maskedPhone = data['maskedPhone'] as String?;
          _step = _ResetStep.otp;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Failed to send OTP.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to send OTP. Check the email address.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOTP() async {
    final otp = _otpValue;
    if (otp.length != 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyPasswordResetOTP')
          .call({'email': _email.text.trim(), 'otp': otp});
      final data = result.data as Map<String, dynamic>;
      if (mounted) {
        _verificationToken = data['verificationToken'] as String? ?? 'otp_verified';
        setState(() => _step = _ResetStep.newPassword);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Invalid OTP.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Verification failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final pw = _newPassword.text;
    final confirm = _confirmPassword.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await FirebaseFunctions.instance
          .httpsCallable('resetUserPassword')
          .call({
        'email': _email.text.trim(),
        'newPassword': pw,
        'verificationToken': _verificationToken,
      });
      if (mounted) setState(() => _step = _ResetStep.success);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Failed to reset password.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOTP() async {
    for (final c in _otpControllers) { c.clear(); }
    setState(() => _error = null);
    await _sendOTP();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [scheme.surface, scheme.primary.withValues(alpha: 0.05), scheme.surface]
                      : [scheme.primary.withValues(alpha: 0.03), scheme.surface, scheme.primaryContainer.withValues(alpha: 0.1)],
                ),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: isDark ? 0.04 : 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiary.withValues(alpha: isDark ? 0.03 : 0.05),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.lock_reset_rounded, size: 28, color: scheme.primary),
                  ),
                  const SizedBox(height: 24),
                  Text('Reset Password', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Text(
                    _stepSubtitle,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 36),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: _buildStepContent(scheme, text),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () => context.go('/setup?signin=1'),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back to Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _stepSubtitle {
    switch (_step) {
      case _ResetStep.email:
        return 'Enter your email and we\'ll send a verification code.';
      case _ResetStep.otp:
        return _phoneSent && _maskedPhone != null
            ? 'Code sent to your email and phone ($_maskedPhone).'
            : 'Code sent to your email address.';
      case _ResetStep.newPassword:
        return 'Set your new password.';
      case _ResetStep.success:
        return 'Your password has been reset successfully.';
    }
  }

  Widget _buildStepContent(ColorScheme scheme, TextTheme text) {
    switch (_step) {
      case _ResetStep.email:
        return _buildEmailStep(scheme, text);
      case _ResetStep.otp:
        return _buildOtpStep(scheme, text);
      case _ResetStep.newPassword:
        return _buildNewPasswordStep(scheme, text);
      case _ResetStep.success:
        return _buildSuccessStep(scheme, text);
    }
  }

  Widget _buildError(ColorScheme scheme) {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildError(scheme),
        Text('Email Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: text.bodyMedium,
          onSubmitted: (_) => _sendOTP(),
          decoration: const InputDecoration(
            hintText: 'you@company.com',
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _sendOTP,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send Verification Code'),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        _buildError(scheme),
        if (_phoneSent && _maskedPhone != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone_android_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Also sent via SMS to $_maskedPhone',
                      style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Container(
              width: 44,
              height: 52,
              margin: EdgeInsets.only(right: i < 5 ? 8 : 0),
              child: TextField(
                controller: _otpControllers[i],
                focusNode: _otpFocusNodes[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty && i < 5) {
                    _otpFocusNodes[i + 1].requestFocus();
                  } else if (val.isEmpty && i > 0) {
                    _otpFocusNodes[i - 1].requestFocus();
                  }
                  if (_otpValue.length == 6) {
                    _verifyOTP();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _verifyOTP,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify Code'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : _resendOTP,
          child: const Text('Resend Code'),
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildError(scheme),
        Text('New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextField(
          controller: _newPassword,
          obscureText: _obscureNew,
          style: text.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Minimum 8 characters',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Confirm Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPassword,
          obscureText: _obscureConfirm,
          style: text.bodyMedium,
          onSubmitted: (_) => _resetPassword(),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _resetPassword,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Reset Password'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2E7D32), size: 28),
        ),
        const SizedBox(height: 16),
        Text('Password Reset!', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF2E7D32))),
        const SizedBox(height: 8),
        Text(
          'Your password has been changed. You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go('/setup?signin=1'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: const Text('Go to Sign In'),
          ),
        ),
      ],
    );
  }
}
