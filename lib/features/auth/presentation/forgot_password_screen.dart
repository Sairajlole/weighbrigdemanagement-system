import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

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
  bool _mfaMode = false; // verify via authenticator instead of email/SMS reset code
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
      // If the account has an authenticator (2FA), use it instead of an email code.
      try {
        final mfa = await CloudFunctionsService.call('mfaStatus', {'email': email});
        if (mfa['enabled'] == true) {
          if (mounted) setState(() { _mfaMode = true; _loading = false; _step = _ResetStep.otp; });
          return;
        }
      } catch (_) {/* fall through to email */}
      _mfaMode = false;
      final data = await CloudFunctionsService.call('sendPasswordResetOTP', {'email': email});
      if (mounted) {
        setState(() {
          _phoneSent = data['phoneSent'] == true;
          _maskedPhone = data['maskedPhone'] as String?;
          _step = _ResetStep.otp;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to send OTP. Check the email address.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fallback to an emailed reset code when MFA was preferred.
  Future<void> _useEmailReset() async {
    setState(() { _mfaMode = false; _loading = true; _error = null; });
    try {
      final data = await CloudFunctionsService.call('sendPasswordResetOTP', {'email': _email.text.trim()});
      if (mounted) setState(() { _phoneSent = data['phoneSent'] == true; _maskedPhone = data['maskedPhone'] as String?; });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to send code.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOTP() async {
    if (_loading) return; // guard: 6-digit onChanged can fire twice
    final otp = _otpValue;
    if (otp.length != 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final data = _mfaMode
          ? await CloudFunctionsService.call('verifyMfaCode', {'email': _email.text.trim(), 'code': otp, 'mintResetToken': true})
          : await CloudFunctionsService.call('verifyPasswordResetOTP', {'email': _email.text.trim(), 'otp': otp});
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? scheme.surface : const Color(0xFFF8FAFB),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ForgotPasswordBgPainter(isDark: isDark),
            ),
          ),
          const Positioned.fill(child: _LogoWatermark()),
          // Content — same layout as welcome step
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              // Brand name — same position as login page
              Text(
                'tulanam',
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  letterSpacing: 2,
                  height: 1,
                ),
              ),
              const SizedBox(height: 36),
              Flexible(
                flex: 7,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Card
                          Container(
                            padding: EdgeInsets.all(32.rs),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(20.rs),
                              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Header
                                Row(
                                  children: [
                                    Container(
                                      width: 40.rs,
                                      height: 40.rs,
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withValues(alpha: 0.1),
                                        borderRadius: AppRadius.button,
                                      ),
                                      child: Icon(Icons.lock_reset_rounded, size: AppSizes.iconMd, color: scheme.primary),
                                    ),
                                    SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Reset Password', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                          SizedBox(height: 2.rs),
                                          Text(
                                            _stepSubtitle,
                                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 24.rs),
                                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                                SizedBox(height: 24.rs),
                                _buildStepContent(scheme, text),
                              ],
                            ),
                          ),
                          SizedBox(height: AppSpacing.xl),
                          TextButton.icon(
                            onPressed: () => context.go('/setup?signin=1'),
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text('Back to Sign In'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _stepSubtitle {
    switch (_step) {
      case _ResetStep.email:
        return 'Enter your email to receive a verification code.';
      case _ResetStep.otp:
        return _mfaMode
            ? 'Enter the code from your authenticator app.'
            : (_phoneSent && _maskedPhone != null
                ? 'Code sent to email and phone ($_maskedPhone).'
                : 'Code sent to your email address.');
      case _ResetStep.newPassword:
        return 'Set your new password.';
      case _ResetStep.success:
        return 'Done! Your password has been reset.';
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
        padding: EdgeInsets.all(12.rs),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
            SizedBox(width: AppSpacing.sm),
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
        Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
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
        SizedBox(height: 20.rs),
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
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: Container(
              padding: EdgeInsets.all(12.rs),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10.rs),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone_android_rounded, size: 16, color: scheme.primary),
                  SizedBox(width: AppSpacing.sm),
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
              width: 44.rs,
              height: 52.rs,
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
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
        SizedBox(height: 20.rs),
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
        SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _loading ? null : (_mfaMode ? _useEmailReset : _resendOTP),
          child: Text(_mfaMode ? 'Send a code to my email instead' : 'Resend Code'),
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
        SizedBox(height: 6.rs),
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
        SizedBox(height: AppSpacing.lg),
        Text('Confirm Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
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
        SizedBox(height: 20.rs),
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
          width: 48.rs,
          height: 48.rs,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2E7D32), size: 24),
        ),
        SizedBox(height: AppSpacing.lg),
        Text('Password Reset!', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF2E7D32))),
        SizedBox(height: AppSpacing.sm),
        Text(
          'You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 20.rs),
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

class _LogoWatermark extends StatefulWidget {
  const _LogoWatermark();

  @override
  State<_LogoWatermark> createState() => _LogoWatermarkState();
}

class _LogoWatermarkState extends State<_LogoWatermark> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = isDark ? 0.03 : 0.05;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (constraints.maxHeight / 160).ceil() + 1;
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final shift = _controller.value * (totalWidth + 200);
            return ClipRect(
              child: Opacity(
                opacity: opacity,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
                  child: Stack(
                    children: List.generate(rows, (row) {
                      return Positioned(
                        top: row * 160.0 - 80,
                        left: shift - totalWidth - 200,
                        width: totalWidth * 3,
                        height: 140,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: double.infinity,
                          child: Row(
                            children: List.generate(24, (col) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 40),
                                child: SizedBox(
                                  width: 100,
                                  height: 92,
                                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ForgotPasswordBgPainter extends CustomPainter {
  final bool isDark;

  _ForgotPasswordBgPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? [const Color(0xFF0F1A2E), const Color(0xFF121212)]
            : [const Color(0xFFF8FAFB), const Color(0xFFF0F7F6)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final dotPaint = Paint()
      ..color = (isDark ? Colors.white : AppTheme.brandNavy).withValues(alpha: 0.04);
    const spacing = 48.0;
    for (var x = 24.0; x < size.width; x += spacing) {
      for (var y = 24.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ForgotPasswordBgPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}
