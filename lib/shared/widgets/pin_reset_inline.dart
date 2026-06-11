import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

/// Inline "set / reset verification PIN" form.
///
/// Setting a PIN for the first time just asks for the new PIN. **Resetting** an
/// existing PIN ([isReset] true) is two steps: the *actor* (the signed-in user
/// performing the change) first verifies — with their authenticator code if 2FA
/// is configured, otherwise a one-time code sent to their email + SMS — and only
/// then is asked for the new PIN.
class PinResetInline extends ConsumerStatefulWidget {
  final String? operatorEmail; // whose PIN; null = the signed-in user (self)
  final String companyId;
  final bool isReset;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const PinResetInline({
    super.key,
    this.operatorEmail,
    required this.companyId,
    required this.isReset,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  ConsumerState<PinResetInline> createState() => _PinResetInlineState();
}

enum _Step { verify, pin }

class _PinResetInlineState extends ConsumerState<PinResetInline> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  String _actorEmail = '';
  String? _method; // 'totp' | 'otp'
  bool _preparing = true;
  bool _busy = false;
  String? _error;
  late _Step _step = widget.isReset ? _Step.verify : _Step.pin;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    _actorEmail = FirebaseAuth.instance.currentUser?.email ??
        await LocalCacheService.getCachedCurrentUserEmail() ?? '';
    if (!widget.isReset) {
      if (mounted) setState(() => _preparing = false);
      return;
    }
    try {
      final r = await CloudFunctionsService.call('sendPinResetChallenge', {'email': _actorEmail});
      if (mounted) setState(() { _method = r['method'] as String? ?? 'otp'; _preparing = false; });
    } catch (e) {
      if (mounted) setState(() { _preparing = false; _error = 'Couldn\'t start verification: $e'; });
    }
  }

  Future<void> _resend() async {
    setState(() { _preparing = true; _error = null; });
    await _prepare();
  }

  // Step 1 — validate the actor's code, then advance to PIN entry.
  Future<void> _verifyCode() async {
    if (_code.text.trim().isEmpty) { setState(() => _error = 'Enter the verification code.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await CloudFunctionsService.call('verifyPinResetCode', {'email': _actorEmail, 'code': _code.text.trim()});
      if (mounted) setState(() { _busy = false; _step = _Step.pin; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = _friendly(e, 'Verification failed. Check the code and try again.'); });
    }
  }

  // Step 2 — set the new PIN (resetOperatorPin requires the grant from step 1).
  Future<void> _savePin() async {
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) { setState(() => _error = 'PIN must be 4-6 digits.'); return; }
    if (pin != _confirm.text.trim()) { setState(() => _error = 'PINs do not match.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      if (widget.isReset) {
        await CloudFunctionsService.call('resetOperatorPin', {
          'actorEmail': _actorEmail,
          'operatorEmail': widget.operatorEmail ?? _actorEmail,
          'companyId': widget.companyId,
          'pin': pin,
        });
      } else {
        await CloudFunctionsService.call('setOperatorPin', {
          'pin': pin,
          'companyId': widget.companyId,
          'operatorEmail': widget.operatorEmail ?? _actorEmail,
        });
      }
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = _friendly(e, 'Couldn\'t save the PIN.'); });
    }
  }

  String _friendly(Object e, String fallback) {
    final s = e.toString();
    if (s.contains('failed-precondition')) return 'Verification expired — verify again.';
    if (s.contains('permission-denied') || s.contains('Verification failed')) return 'Verification failed. Check the code and try again.';
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_preparing) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8.rs),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: AppSpacing.sm),
            Text('Starting verification…', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return _step == _Step.verify ? _buildVerifyStep(scheme) : _buildPinStep(scheme);
  }

  Widget _buildVerifyStep(ColorScheme scheme) {
    final hint = _method == 'totp'
        ? 'Enter the code from your authenticator app.'
        : 'Enter the code sent to your email & SMS.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hint, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                onSubmitted: (_) => _verifyCode(),
                decoration: const InputDecoration(isDense: true, labelText: 'Verification code', counterText: ''),
              ),
            ),
            if (_method != 'totp') ...[
              SizedBox(width: AppSpacing.xs),
              TextButton(onPressed: _busy ? null : _resend, child: const Text('Resend', style: TextStyle(fontSize: 11))),
            ],
            SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : _verifyCode,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), textStyle: const TextStyle(fontSize: 11)),
              child: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify'),
            ),
            SizedBox(width: AppSpacing.xs),
            TextButton(
              onPressed: _busy ? null : widget.onCancel,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
              child: const Text('Cancel'),
            ),
          ],
        ),
        if (_error != null) ...[
          SizedBox(height: 6.rs),
          Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error)),
        ],
      ],
    );
  }

  Widget _buildPinStep(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isReset) ...[
          Row(
            children: [
              Icon(Icons.verified_user_rounded, size: 13, color: AppTheme.successColor),
              SizedBox(width: AppSpacing.xs),
              Text('Identity verified — set a new PIN', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pin,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: const InputDecoration(isDense: true, labelText: 'New PIN', counterText: ''),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: _confirm,
                obscureText: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                onSubmitted: (_) => _savePin(),
                decoration: const InputDecoration(isDense: true, labelText: 'Confirm', counterText: ''),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : _savePin,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), textStyle: const TextStyle(fontSize: 11)),
              child: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
            SizedBox(width: AppSpacing.xs),
            TextButton(
              onPressed: _busy ? null : widget.onCancel,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
              child: const Text('Cancel'),
            ),
          ],
        ),
        if (_error != null) ...[
          SizedBox(height: 6.rs),
          Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error)),
        ],
      ],
    );
  }
}
