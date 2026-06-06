import 'package:flutter/foundation.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

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
      final data = await CloudFunctionsService.call('sendPasswordResetOTP', {'email': email});
      if (mounted) {
        setState(() {
          _phoneSent = data['phoneSent'] == true;
          _maskedPhone = data['maskedPhone'] as String?;
          _step = _ResetStep.otp;
        });
      }
    } catch (e) {
      debugPrint('[ForgotPassword] sendOTP error: $e');
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
      final data = await CloudFunctionsService.call('verifyPasswordResetOTP', {'email': _email.text.trim(), 'otp': otp});
      if (mounted) {
        _verificationToken = data['verificationToken'] as String? ?? 'otp_verified';
        setState(() => _step = _ResetStep.newPassword);
      }
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
      await CloudFunctionsService.call('resetUserPassword', {
        'email': _email.text.trim(),
        'newPassword': pw,
        'verificationToken': _verificationToken,
      });
      if (mounted) setState(() => _step = _ResetStep.success);
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
    debugPrint('[ForgotPassword] build called, step=$_step');
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
          Center(
            child: SingleChildScrollView(
              padding: AppSpacing.pagePadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72.rs,
                    height: 72.rs,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.lock_reset_rounded, size: AppSizes.iconXl, color: scheme.primary),
                  ),
                  SizedBox(height: AppSpacing.xl),
                  Text('Reset Password', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    _stepSubtitle,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 36.rs),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 460.rs),
                    child: Container(
                      padding: EdgeInsets.all(32.rs),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                        boxShadow: AppElevation.elevated(Colors.black),
                      ),
                      child: _buildStepContent(scheme, text),
                    ),
                  ),
                  SizedBox(height: AppSpacing.xl),
                  TextButton.icon(
                    onPressed: () => context.go('/setup?signin=1'),
                    icon: Icon(Icons.arrow_back_rounded, size: AppSizes.iconSm),
                    label: Text('Back to Sign In', style: TextStyle(fontSize: 14.rs)),
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
      padding: EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: AppRadius.input,
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: AppSizes.iconMd, color: scheme.error),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(_error!, style: TextStyle(fontSize: 13.rs, color: scheme.error, fontWeight: FontWeight.w500))),
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
        Text('Email Address', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: text.bodyLarge,
          onSubmitted: (_) => _sendOTP(),
          decoration: InputDecoration(
            hintText: 'you@company.com',
            prefixIcon: Icon(Icons.email_outlined, size: AppSizes.iconMd),
          ),
        ),
        SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          height: AppSizes.buttonHeight,
          child: FilledButton(
            onPressed: _loading ? null : _sendOTP,
            child: _loading
                ? SizedBox(width: 20.rs, height: 20.rs, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Send Verification Code', style: TextStyle(fontSize: 15.rs, fontWeight: FontWeight.w600)),
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
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: AppRadius.input,
              ),
              child: Row(
                children: [
                  Icon(Icons.phone_android_rounded, size: AppSizes.iconMd, color: scheme.primary),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Also sent via SMS to $_maskedPhone',
                      style: TextStyle(fontSize: 13.rs, color: scheme.primary, fontWeight: FontWeight.w500),
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
              width: 48.rs,
              height: 56.rs,
              margin: EdgeInsets.only(right: i < 5 ? 8.rs : 0),
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
                  contentPadding: EdgeInsets.symmetric(vertical: 12.rs),
                  border: OutlineInputBorder(borderRadius: AppRadius.input),
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
        SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          height: AppSizes.buttonHeight,
          child: FilledButton(
            onPressed: _loading ? null : _verifyOTP,
            child: _loading
                ? SizedBox(width: 20.rs, height: 20.rs, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Verify Code', style: TextStyle(fontSize: 15.rs, fontWeight: FontWeight.w600)),
          ),
        ),
        SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _loading ? null : _resendOTP,
          child: Text('Resend Code', style: TextStyle(fontSize: 14.rs)),
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildError(scheme),
        Text('New Password', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _newPassword,
          obscureText: _obscureNew,
          style: text.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Minimum 8 characters',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: AppSizes.iconMd),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: AppSizes.iconMd),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        Text('Confirm Password', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _confirmPassword,
          obscureText: _obscureConfirm,
          style: text.bodyLarge,
          onSubmitted: (_) => _resetPassword(),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: AppSizes.iconMd),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: AppSizes.iconMd),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          height: AppSizes.buttonHeight,
          child: FilledButton(
            onPressed: _loading ? null : _resetPassword,
            child: _loading
                ? SizedBox(width: 20.rs, height: 20.rs, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Reset Password', style: TextStyle(fontSize: 15.rs, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: 64.rs,
          height: 64.rs,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle_outline_rounded, color: const Color(0xFF2E7D32), size: AppSizes.iconXl),
        ),
        SizedBox(height: AppSpacing.lg),
        Text('Password Reset!', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF2E7D32))),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Your password has been changed. You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          height: AppSizes.buttonHeight,
          child: FilledButton(
            onPressed: () => context.go('/setup?signin=1'),
            child: Text('Go to Sign In', style: TextStyle(fontSize: 15.rs, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
