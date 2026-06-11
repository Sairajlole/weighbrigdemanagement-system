import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/address_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

/// General-settings card for the mailed address-verification code. Shows the
/// trust badge (verified / action-needed / overdue) and lets the admin enter
/// the code from the posted letter to confirm the company within the window.
class AddressVerificationCard extends ConsumerStatefulWidget {
  const AddressVerificationCard({super.key});

  @override
  ConsumerState<AddressVerificationCard> createState() => _AddressVerificationCardState();
}

class _AddressVerificationCardState extends ConsumerState<AddressVerificationCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = 'Enter the code printed on your letter.');
      return;
    }
    setState(() { _busy = true; _error = null; _success = null; });
    try {
      final companyId = ref.read(firestorePathsProvider).context.companyId;
      await CloudFunctionsService.call('verifyAddressCode', {'companyId': companyId, 'code': code});
      // The addressVerificationProvider stream will flip to "verified".
      if (mounted) setState(() { _busy = false; _success = 'Address verified — thank you!'; _code.clear(); });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message ?? 'Verification failed.'; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Verification failed. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final av = ref.watch(addressVerificationProvider).valueOrNull;

    final status = av?.status ?? 'pending';
    final verified = status == 'verified';
    final grace = av?.graceUntil;
    final overdue = !verified && grace != null && grace.isBefore(DateTime.now());
    final daysLeft = (grace != null && !overdue) ? grace.difference(DateTime.now()).inDays : null;

    final accent = verified
        ? AppTheme.successColor
        : (overdue ? scheme.error : Colors.orange);

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: AppRadius.card,
        border: Border.all(color: accent.withValues(alpha: verified ? 0.25 : 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(verified ? Icons.verified_rounded : Icons.markunread_mailbox_rounded, size: 18, color: accent),
              SizedBox(width: AppSpacing.sm),
              Text('Address Verification', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              _badge(verified, overdue, daysLeft, accent),
            ],
          ),
          SizedBox(height: AppSpacing.md),

          if (verified) ...[
            Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.successColor),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Your registered company address is confirmed. No action needed.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4))),
              ],
            ),
          ] else ...[
            Text(
              overdue
                  ? 'The verification window has passed. Enter the code from the letter we posted to your registered company address to restore full access.'
                  : 'We posted a letter with a verification code to your registered company address. Enter it here to confirm your company'
                      '${daysLeft != null ? ' — $daysLeft day${daysLeft == 1 ? '' : 's'} left.' : ' within the window.'}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      UpperCaseFormatter(),
                    ],
                    onSubmitted: (_) => _verify(),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Verification code',
                      hintText: 'e.g. 7K2P9QF4',
                      border: OutlineInputBorder(borderRadius: AppRadius.button),
                      prefixIcon: const Icon(Icons.markunread_mailbox_outlined, size: 18),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _busy ? null : _verify,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                  child: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Verify'),
                ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: 8.rs),
              Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
            ],
            if (_success != null) ...[
              SizedBox(height: 8.rs),
              Text(_success!, style: text.bodySmall?.copyWith(color: AppTheme.successColor)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _badge(bool verified, bool overdue, int? daysLeft, Color accent) {
    final label = verified
        ? 'Verified'
        : (overdue ? 'Overdue' : (daysLeft != null ? '$daysLeft day${daysLeft == 1 ? '' : 's'} left' : 'Action needed'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: AppRadius.chip),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
    );
  }
}

/// Forces typed text to upper-case (verification codes are case-insensitive but
/// shown upper).
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
