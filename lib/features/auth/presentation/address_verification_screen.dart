import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

/// Shown once the 30-day grace window lapses and the company's address is still
/// unverified. The user enters the code from the posted letter to unlock the app.
class AddressVerificationScreen extends ConsumerStatefulWidget {
  const AddressVerificationScreen({super.key});

  @override
  ConsumerState<AddressVerificationScreen> createState() => _AddressVerificationScreenState();
}

class _AddressVerificationScreenState extends ConsumerState<AddressVerificationScreen> {
  final _code = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _submitting = true; _error = null; });
    try {
      final companyId = ref.read(firestorePathsProvider).context.companyId;
      final res = await CloudFunctionsService.call('verifyAddressCode', {
        'companyId': companyId,
        'code': code,
      });
      if (res['verified'] == true) {
        // The address_verifications stream will flip to 'verified' and the
        // router gate will route the user back into the app automatically.
        return;
      }
      if (mounted) setState(() => _error = 'Incorrect code. Please check the letter and try again.');
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('Too many attempts')) {
      final m = RegExp(r'Too many attempts[^.]*').firstMatch(s);
      return m?.group(0) ?? 'Too many attempts. Please try again later.';
    }
    if (s.contains('Incorrect code')) return 'Incorrect code. Please check the letter and try again.';
    if (s.contains('not-found') || s.contains('No verification')) {
      return 'No verification is pending for this company. Contact support.';
    }
    return 'Could not verify the code. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: AppRadius.dialog,
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                boxShadow: AppElevation.card(scheme.shadow),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: AppRadius.button,
                    ),
                    child: Icon(Icons.markunread_mailbox_outlined, color: scheme.primary, size: 26),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  Text('Verify your business address',
                      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'A letter with a one-time code was posted to your registered company address. '
                    'Enter the code to keep using the app. Your 30-day trial window has ended.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                  ),
                  SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    onSubmitted: (_) => _verify(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      fontFamily: 'Courier',
                    ),
                    decoration: InputDecoration(
                      hintText: 'XXXXXXXX',
                      counterText: '',
                      hintStyle: TextStyle(
                        fontSize: 26,
                        letterSpacing: 8,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                      border: OutlineInputBorder(borderRadius: AppRadius.card),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.card,
                        borderSide: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _verify,
                      icon: _submitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.lock_open_rounded, size: 18),
                      label: Text(_submitting ? 'Verifying…' : 'Verify & unlock'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  Text(
                    "Didn't receive the letter? Contact support to have it re-sent.",
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
