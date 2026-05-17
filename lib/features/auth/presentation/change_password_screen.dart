import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  final String reason;
  const ChangePasswordScreen({super.key, required this.reason});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _totpCode = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _hasMfa = false;

  @override
  void initState() {
    super.initState();
    _checkMfaStatus();
  }

  Future<void> _checkMfaStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final factors = await user.multiFactor.getEnrolledFactors();
    if (mounted) setState(() => _hasMfa = factors.isNotEmpty);
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _totpCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasMfa && _totpCode.text.trim().length < 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(email: user.email!, password: _currentPassword.text);

      try {
        await user.reauthenticateWithCredential(cred);
      } on FirebaseAuthMultiFactorException catch (e) {
        final code = _totpCode.text.trim();
        final hint = e.resolver.hints.first;
        final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(hint.uid, code);
        await e.resolver.resolveSignIn(assertion);
      }

      await _applyPasswordChange(user);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        setState(() => _error = 'Current password is incorrect.');
      } else if (e.code == 'invalid-verification-code') {
        setState(() => _error = 'Invalid 2FA code. Check your authenticator app.');
      } else {
        setState(() => _error = 'Failed: ${e.message}');
      }
    } catch (e) {
      setState(() => _error = 'Failed to change password.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyPasswordChange(User user) async {
    await user.updatePassword(_newPassword.text);

    final paths = ref.read(firestorePathsProvider);
    if (paths.isConfigured) {
      final snap = await paths.operators.where('email', isEqualTo: user.email).limit(1).get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({
          'passwordLastChanged': FieldValue.serverTimestamp(),
          'mustChangePassword': false,
        });
      } else {
        await paths.siteSetting('adminProfile').set({
          'passwordLastChanged': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_reset_rounded, size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                Text('Change Password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                  child: Text(widget.reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(fontSize: 12, color: scheme.onErrorContainer)),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _currentPassword,
                  obscureText: _obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPassword,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                    suffixIcon: IconButton(icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => _obscureNew = !_obscureNew)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) return 'Minimum 8 characters';
                    if (!v.contains(RegExp(r'[0-9]'))) return 'Must contain a number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v != _newPassword.text ? 'Passwords do not match' : null,
                ),

                // 2FA field — shown inline if MFA is enrolled
                if (_hasMfa) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.tertiary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.security_rounded, size: 16, color: scheme.tertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '2FA is enabled — enter your authenticator code',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _totpCode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 6),
                    decoration: InputDecoration(
                      labelText: '2FA Code',
                      hintText: '000000',
                      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.3), letterSpacing: 6),
                      counterText: '',
                      prefixIcon: const Icon(Icons.pin_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Change Password'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
