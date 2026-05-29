import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/mfa_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';

class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  bool _loading = true;
  bool _enrolling = false;
  List<MultiFactorInfo> _factors = [];
  TotpSecret? _totpSecret;
  String? _error;
  String? _success;
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFactors();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadFactors() async {
    setState(() => _loading = true);
    try {
      final mfa = ref.read(mfaServiceProvider);
      _factors = await mfa.getEnrolledFactors();
    } catch (e) {
      _error = 'Failed to load MFA status.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _startEnrollment() async {
    setState(() { _enrolling = true; _error = null; _success = null; });
    try {
      final mfa = ref.read(mfaServiceProvider);
      _totpSecret = await mfa.enrollTotp();
    } catch (e) {
      _error = 'Failed to generate secret. You may need to re-authenticate.';
    }
    if (mounted) setState(() => _enrolling = false);
  }

  Future<void> _finalizeEnrollment() async {
    if (_otpController.text.length != 6) {
      setState(() => _error = 'Enter a valid 6-digit code.');
      return;
    }
    setState(() { _enrolling = true; _error = null; });
    try {
      final mfa = ref.read(mfaServiceProvider);
      await mfa.finalizeEnrollment(_totpSecret!, _otpController.text.trim());
      _totpSecret = null;
      _otpController.clear();
      _success = 'MFA enrolled successfully!';
      await _loadFactors();
    } on FirebaseAuthException catch (e) {
      _error = e.code == 'invalid-verification-code'
          ? 'Invalid code. Check your authenticator app.'
          : 'Enrollment failed: ${e.message}';
    } catch (e) {
      _error = 'Enrollment failed. Please try again.';
    }
    if (mounted) setState(() => _enrolling = false);
  }

  Future<void> _removeFactor(MultiFactorInfo factor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove MFA'),
        content: const Text('Are you sure you want to disable two-factor authentication?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _loading = true; _error = null; });
    try {
      final mfa = ref.read(mfaServiceProvider);
      await mfa.unenrollFactor(factor);
      _success = 'MFA removed.';
      await _loadFactors();
    } catch (e) {
      _error = 'Failed to remove. You may need to re-authenticate.';
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: Padding(
        padding: EdgeInsets.all(24.rs),
        child: _loading
            ? const AppLoading()
            : SingleChildScrollView(child: _buildContent(scheme, text)),
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(20.rs),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _factors.isNotEmpty ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12.rs),
                ),
                child: Icon(
                  _factors.isNotEmpty ? Icons.verified_user_rounded : Icons.shield_outlined,
                  color: _factors.isNotEmpty ? const Color(0xFF2E7D32) : Colors.grey.shade500,
                ),
              ),
              SizedBox(width: 16.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    SizedBox(height: 2.rs),
                    Text(
                      _factors.isNotEmpty ? 'MFA Enabled' : 'MFA Not Enabled',
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (_factors.isEmpty && _totpSecret == null)
                FilledButton.icon(
                  onPressed: _enrolling ? null : _startEnrollment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Enable'),
                ),
            ],
          ),
        ),
        SizedBox(height: 20.rs),

        if (_error != null) ...[
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: const Color(0xFFEF9A9A).withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE53935)),
              SizedBox(width: 10.rs),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFC62828)))),
            ]),
          ),
          SizedBox(height: 16.rs),
        ],

        if (_success != null) ...[
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 18, color: Color(0xFF2E7D32)),
              SizedBox(width: 10.rs),
              Expanded(child: Text(_success!, style: const TextStyle(fontSize: 13, color: Color(0xFF1B5E20)))),
            ]),
          ),
          SizedBox(height: 16.rs),
        ],

        if (_totpSecret != null) _buildEnrollmentCard(scheme, text),

        if (_factors.isNotEmpty) ...[
          Text('Enrolled Factors', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 12.rs),
          ..._factors.map((f) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.security, size: 20, color: Color(0xFF2E7D32)),
                SizedBox(width: 12.rs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.displayName ?? 'Authenticator App', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      Text('Enrolled: ${DateTime.fromMillisecondsSinceEpoch((f.enrollmentTimestamp * 1000).toInt()).toString().split('.').first}',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _removeFactor(f),
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'Remove',
                ),
              ],
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildEnrollmentCard(ColorScheme scheme, TextTheme text) {
    final uri = _totpSecret!.generateQrCodeUrl(
      accountName: FirebaseAuth.instance.currentUser?.email ?? 'user',
      issuer: 'WeighbridgeManager',
    );
    final secretKey = _totpSecret!.secretKey;

    return Container(
      padding: EdgeInsets.all(20.rs),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16.rs),
        border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set Up Authenticator', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 8.rs),
          Text('Open your authenticator app (Google Authenticator, Authy, etc.) and add a new account.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(height: 16.rs),

          Text('Manual Entry Key:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 6.rs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(secretKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: secretKey));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Secret key copied to clipboard')),
                    );
                  },
                  tooltip: 'Copy',
                ),
              ],
            ),
          ),
          SizedBox(height: 8.rs),
          SelectableText('URI: $uri', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
          SizedBox(height: 20.rs),

          Text('Enter the 6-digit code from your app:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 8.rs),
          Row(
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: '000000',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs), borderSide: const BorderSide(color: Color(0xFF43A047), width: 2)),
                  ),
                ),
              ),
              SizedBox(width: 12.rs),
              FilledButton(
                onPressed: _enrolling ? null : _finalizeEnrollment,
                child: _enrolling
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify & Enable'),
              ),
            ],
          ),
          SizedBox(height: 12.rs),
          TextButton(
            onPressed: () => setState(() { _totpSecret = null; _error = null; }),
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
